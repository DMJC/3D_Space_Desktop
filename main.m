#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GL/gl.h>
#import <math.h>

typedef struct { float x,y,z; } Vec3;
static inline float DegToRad(float d){ return d*(float)M_PI/180.f; }
static NSString *NormalizeScenePath(NSString *raw){ return [[raw stringByReplacingOccurrencesOfString:@"\\ " withString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; }

@interface SceneModel : NSObject
@property(nonatomic,copy) NSString *pofPath;
@property(nonatomic) Vec3 position;
@property(nonatomic) BOOL hasOvalPath;
@property(nonatomic) float ovalRadius, ovalSpeedDegPerSec, ovalAngleOffset;
@end
@implementation SceneModel @end

@interface SceneDefinition : NSObject
@property(nonatomic) Vec3 cameraPosition;
@property(nonatomic,copy) NSString *textureRoot,*skyboxName;
@property(nonatomic) BOOL showLoops;
@property(nonatomic,strong) NSMutableArray *models;
@end
@implementation SceneDefinition
- (instancetype)init{ if((self=[super init])){ _cameraPosition=(Vec3){0,0,30}; _models=[NSMutableArray array]; } return self; }
@end

@interface SceneParser : NSObject + (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error; @end
@implementation SceneParser
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error { NSString *raw=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error]; if(!raw) return nil; SceneDefinition *scene=[SceneDefinition new];
for(NSString *lineRaw in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){ NSString *line=[[[lineRaw componentsSeparatedByString:@"#"] objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if(!line.length) continue; NSRange eq=[line rangeOfString:@"="]; if(eq.location==NSNotFound) continue; NSString *key=[[[line substringToIndex:eq.location] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; NSString *value=NormalizeScenePath([line substringFromIndex:eq.location+1]);
if([key isEqualToString:@"camera"]){ NSArray *c=[value componentsSeparatedByString:@","]; if(c.count>=3) scene.cameraPosition=(Vec3){[c[0] floatValue],[c[1] floatValue],[c[2] floatValue]}; }
else if([key isEqualToString:@"textureroot"]) scene.textureRoot=value;
else if([key isEqualToString:@"skybox"]) scene.skyboxName=value.length?value:nil;
else if([key isEqualToString:@"showloops"]) scene.showLoops=[[value lowercaseString] isEqualToString:@"true"];
else if([key isEqualToString:@"model"]) { NSArray *chunks=[value componentsSeparatedByString:@","]; if(chunks.count<4) continue; SceneModel *m=[SceneModel new]; m.pofPath=NormalizeScenePath(chunks[0]); m.position=(Vec3){[chunks[1] floatValue],[chunks[2] floatValue],[chunks[3] floatValue]}; for(NSUInteger i=4;i<chunks.count;i++){ NSArray *kv=[[[chunks[i] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@"="]; if(kv.count!=2) continue; if([kv[0] isEqualToString:@"ovalpath"]) m.hasOvalPath=[kv[1] isEqualToString:@"true"]; else if([kv[0] isEqualToString:@"radius"]) m.ovalRadius=[kv[1] floatValue]; else if([kv[0] isEqualToString:@"speed"]) m.ovalSpeedDegPerSec=[kv[1] floatValue]; else if([kv[0] isEqualToString:@"offset"]) m.ovalAngleOffset=[kv[1] floatValue]; } [scene.models addObject:m]; }} return scene; }
@end

typedef struct { float x,y,z; } V3;
@interface POFMesh : NSObject
@property(nonatomic,strong) NSMutableData *verts; // V3
@property(nonatomic,strong) NSMutableData *tris;  // unsigned short *3
@property(nonatomic) float spinRate;
@end
@implementation POFMesh @end

static uint32_t ReadU32(const uint8_t *b){ return (uint32_t)b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24); }
static float ReadF32(const uint8_t *b){ float f; memcpy(&f,b,4); return f; }

static POFMesh *LoadPOFDetail0(NSString *path, NSString **errorMsg) {
    NSData *d=[NSData dataWithContentsOfFile:path]; if(!d || d.length<16){ if(errorMsg)*errorMsg=@"file missing/unreadable"; return nil; }
    const uint8_t *b=d.bytes; if(!(b[0]=='P'&&b[1]=='S'&&b[2]=='P'&&b[3]=='O')){ if(errorMsg)*errorMsg=@"bad PSPO signature"; return nil; }
    POFMesh *mesh=[POFMesh new]; mesh.verts=[NSMutableData data]; mesh.tris=[NSMutableData data]; mesh.spinRate=20.f;
    // Minimal detail0 decode: scan for first IDATA-like block that stores packed xyz triples after marker "D0V0" and triangle indices after "D0I0".
    // This is a pragmatic lightweight decoder used by this viewer; unsupported files gracefully fallback.
    NSUInteger i=0; while(i+8<d.length){
        if(memcmp(b+i,"D0V0",4)==0){ uint32_t count=ReadU32(b+i+4); NSUInteger off=i+8; if(off+count*12<=d.length){ for(uint32_t n=0;n<count;n++){ V3 v={ReadF32(b+off+n*12),ReadF32(b+off+n*12+4),ReadF32(b+off+n*12+8)}; [mesh.verts appendBytes:&v length:sizeof(V3)]; } } }
        if(memcmp(b+i,"D0I0",4)==0){ uint32_t tcount=ReadU32(b+i+4); NSUInteger off=i+8; if(off+tcount*6<=d.length){ [mesh.tris appendBytes:b+off length:tcount*6]; } }
        if(memcmp(b+i,"SPIN",4)==0 && i+8<=d.length){ mesh.spinRate=ReadF32(b+i+4); }
        i++;
    }
    if(mesh.verts.length==0 || mesh.tris.length==0){ if(errorMsg)*errorMsg=@"detail0 mesh blocks not found"; return nil; }
    if(errorMsg)*errorMsg=[NSString stringWithFormat:@"detail0 verts=%lu tris=%lu",(unsigned long)(mesh.verts.length/sizeof(V3)),(unsigned long)(mesh.tris.length/6)];
    return mesh;
}

static void DrawCube(float s){ float h=s*0.5f; glBegin(GL_QUADS); glVertex3f(-h,-h,h);glVertex3f(h,-h,h);glVertex3f(h,h,h);glVertex3f(-h,h,h); glVertex3f(-h,-h,-h);glVertex3f(-h,h,-h);glVertex3f(h,h,-h);glVertex3f(h,-h,-h); glVertex3f(-h,h,-h);glVertex3f(-h,h,h);glVertex3f(h,h,h);glVertex3f(h,h,-h); glVertex3f(-h,-h,-h);glVertex3f(h,-h,-h);glVertex3f(h,-h,h);glVertex3f(-h,-h,h); glVertex3f(h,-h,-h);glVertex3f(h,h,-h);glVertex3f(h,h,h);glVertex3f(h,-h,h); glVertex3f(-h,-h,-h);glVertex3f(-h,-h,h);glVertex3f(-h,h,h);glVertex3f(-h,h,-h); glEnd(); }
static void DrawMesh(POFMesh *m){ const V3 *v=(const V3*)m.verts.bytes; const uint16_t *idx=(const uint16_t*)m.tris.bytes; NSUInteger triCount=m.tris.length/6; glBegin(GL_TRIANGLES); for(NSUInteger t=0;t<triCount;t++){ for(int k=0;k<3;k++){ uint16_t ii=idx[t*3+k]; if(ii<m.verts.length/sizeof(V3)) glVertex3f(v[ii].x,v[ii].y,v[ii].z); }} glEnd(); }

@interface SpaceGLView : NSOpenGLView
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene;
@end
@implementation SpaceGLView { SceneDefinition *_scene; NSTimer *_timer; NSTimeInterval _last; float _elapsed; NSMutableDictionary *_meshCache; NSMutableSet *_loggedPOFs; NSMutableData *_stars; }
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene { NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFADoubleBuffer,NSOpenGLPFAColorSize,24,NSOpenGLPFADepthSize,24,0}; if((self=[super initWithFrame:frame pixelFormat:[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs]])){ _scene=scene; _last=[NSDate timeIntervalSinceReferenceDate]; _timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(onTick:) userInfo:nil repeats:YES]; _meshCache=[NSMutableDictionary dictionary]; _loggedPOFs=[NSMutableSet set]; _stars=[NSMutableData dataWithLength:sizeof(V3)*1500]; V3 *s=(V3*)_stars.mutableBytes; for(int i=0;i<1500;i++){ s[i]=(V3){((float)arc4random()/UINT32_MAX-0.5f)*3000.f,((float)arc4random()/UINT32_MAX-0.5f)*3000.f,-((float)arc4random()/UINT32_MAX)*3000.f}; }} return self; }
- (void)onTick:(NSTimer*)t { (void)t; [self display]; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)e { NSString *c=[e charactersIgnoringModifiers]; if(c.length && [c characterAtIndex:0]==27){ [NSApp terminate:nil]; return; } [super keyDown:e]; }
- (void)prepareOpenGL { [super prepareOpenGL]; glEnable(GL_DEPTH_TEST); }
- (void)reshape { [super reshape]; NSRect b=[self bounds]; glViewport(0,0,b.size.width,b.size.height); glMatrixMode(GL_PROJECTION); glLoadIdentity(); float asp=b.size.height>0?b.size.width/b.size.height:1, n=.1f,f=6000.f,tanfov=tanf(DegToRad(30))*n,r=tanfov*asp; glFrustum(-r,r,-tanfov,tanfov,n,f); }
- (void)drawStarField { glDisable(GL_DEPTH_TEST); glPointSize(2.f); glColor3f(1,1,1); glBegin(GL_POINTS); V3 *s=(V3*)_stars.bytes; for(int i=0;i<1500;i++) glVertex3f(s[i].x,s[i].y,s[i].z); glEnd(); glEnable(GL_DEPTH_TEST); }
- (void)drawRect:(NSRect)r { (void)r; NSTimeInterval n=[NSDate timeIntervalSinceReferenceDate]; _elapsed += (float)(n-_last); _last=n; glClearColor(0.01,0.01,0.03,1); glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT); glMatrixMode(GL_MODELVIEW); glLoadIdentity(); glTranslatef(-_scene.cameraPosition.x,-_scene.cameraPosition.y,-_scene.cameraPosition.z);
    if(!_scene.skyboxName.length) [self drawStarField];
    for(SceneModel *m in _scene.models){ Vec3 p=m.position; if(m.hasOvalPath&&m.ovalRadius>0){ float a=DegToRad(m.ovalAngleOffset+_elapsed*m.ovalSpeedDegPerSec); p.x+=cosf(a)*m.ovalRadius; p.z+=sinf(a)*m.ovalRadius; }
        glPushMatrix(); glTranslatef(p.x,p.y,p.z);
        POFMesh *mesh=[_meshCache objectForKey:m.pofPath]; if((id)mesh==[NSNull null]) mesh=nil;
        if(!mesh && ![_meshCache objectForKey:m.pofPath]){ NSString *err=nil; mesh=LoadPOFDetail0(m.pofPath,&err); if(mesh) [_meshCache setObject:mesh forKey:m.pofPath]; else [_meshCache setObject:[NSNull null] forKey:m.pofPath]; if(![_loggedPOFs containsObject:m.pofPath]){ NSLog(@"[POF] %@ -> %@", m.pofPath, err); [_loggedPOFs addObject:m.pofPath]; }}
        if(mesh){ glRotatef(_elapsed*mesh.spinRate,0,1,0); glColor3f(0.6,0.8,1); DrawMesh(mesh); }
        else { glColor3f(1,0.1,0.1); DrawCube(12.f); }
        glPopMatrix();
        if(_scene.showLoops && m.hasOvalPath && m.ovalRadius>0){ glColor3f(1,0,0); glLineWidth(3); glBegin(GL_LINE_LOOP); for(int i=0;i<96;i++){ float a=DegToRad(360.f*i/96.f); glVertex3f(m.position.x+cosf(a)*m.ovalRadius,m.position.y,m.position.z+sinf(a)*m.ovalRadius);} glEnd(); }
    }
    [[self openGLContext] flushBuffer]; }
@end

int main(int argc,char **argv){ NSAutoreleasePool *pool=[NSAutoreleasePool new]; NSString *scenePath=@"scene.txt"; if(argc>1) scenePath=[NSString stringWithUTF8String:argv[1]]; NSError *err=nil; SceneDefinition *scene=[SceneParser parseSceneAtPath:scenePath error:&err]; if(!scene){ fprintf(stderr,"scene load failed: %s\n",[[err description] UTF8String]); return 1; } [NSApplication sharedApplication]; NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,720) styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO]; [w setTitle:@"3D Scene Viewer (GNUstep)"]; SpaceGLView *view=[[SpaceGLView alloc] initWithFrame:NSMakeRect(0,0,1280,720) scene:scene]; [w setContentView:view]; [w makeFirstResponder:view]; [w makeKeyAndOrderFront:nil]; [NSApp run]; [pool drain]; return 0; }
