#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GL/gl.h>
#import <math.h>

typedef struct { float x,y,z; } Vec3;
static inline float DegToRad(float d){ return d*(float)M_PI/180.f; }
static NSString *NormalizeScenePath(NSString *raw){ return [[raw stringByReplacingOccurrencesOfString:@"\\ " withString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; }

@interface SceneModel : NSObject @property(nonatomic,copy) NSString *pofPath; @property(nonatomic) Vec3 position; @property(nonatomic) BOOL hasOvalPath; @property(nonatomic) float ovalRadius, ovalSpeedDegPerSec, ovalAngleOffset; @end
@implementation SceneModel @end
@interface SceneDefinition : NSObject @property(nonatomic) Vec3 cameraPosition; @property(nonatomic,copy) NSString *textureRoot,*skyboxName; @property(nonatomic) BOOL showLoops; @property(nonatomic,strong) NSMutableArray *models; @end
@implementation SceneDefinition - (instancetype)init{ if((self=[super init])){ _cameraPosition=(Vec3){0,0,30}; _models=[NSMutableArray array]; } return self; } @end

@interface SceneParser : NSObject + (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error; @end
@implementation SceneParser
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error { NSString *raw=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error]; if(!raw) return nil; SceneDefinition *s=[SceneDefinition new]; for(NSString *lr in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){ NSString *line=[[[lr componentsSeparatedByString:@"#"] objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if(!line.length) continue; NSRange eq=[line rangeOfString:@"="]; if(eq.location==NSNotFound) continue; NSString *k=[[[line substringToIndex:eq.location] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; NSString *v=NormalizeScenePath([line substringFromIndex:eq.location+1]); if([k isEqualToString:@"camera"]){ NSArray *c=[v componentsSeparatedByString:@","]; if(c.count>=3) s.cameraPosition=(Vec3){[c[0] floatValue],[c[1] floatValue],[c[2] floatValue]}; } else if([k isEqualToString:@"textureroot"]) s.textureRoot=v; else if([k isEqualToString:@"skybox"]) s.skyboxName=v.length?v:nil; else if([k isEqualToString:@"showloops"]) s.showLoops=[[v lowercaseString] isEqualToString:@"true"]; else if([k isEqualToString:@"model"]){ NSArray *ch=[v componentsSeparatedByString:@","]; if(ch.count<4) continue; SceneModel *m=[SceneModel new]; m.pofPath=NormalizeScenePath(ch[0]); m.position=(Vec3){[ch[1] floatValue],[ch[2] floatValue],[ch[3] floatValue]}; for(NSUInteger i=4;i<ch.count;i++){ NSArray *kv=[[[ch[i] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@"="]; if(kv.count!=2) continue; if([kv[0] isEqualToString:@"ovalpath"]) m.hasOvalPath=[kv[1] isEqualToString:@"true"]; else if([kv[0] isEqualToString:@"radius"]) m.ovalRadius=[kv[1] floatValue]; else if([kv[0] isEqualToString:@"speed"]) m.ovalSpeedDegPerSec=[kv[1] floatValue]; else if([kv[0] isEqualToString:@"offset"]) m.ovalAngleOffset=[kv[1] floatValue]; } [s.models addObject:m]; }} return s; }
@end

typedef struct { float x,y,z; } V3; static uint32_t U32(const uint8_t *p){ return p[0]|(p[1]<<8)|(p[2]<<16)|(p[3]<<24);} static float F32(const uint8_t *p){ float f; memcpy(&f,p,4); return f; }
@interface POFSub : NSObject @property(nonatomic) int sid,parent; @property(nonatomic,strong) NSMutableData *verts,*tris,*glow; @property(nonatomic) BOOL rotates; @property(nonatomic) float spin; @property(nonatomic,copy) NSString *tex; @end
@implementation POFSub @end
@interface POFMesh : NSObject @property(nonatomic,strong) NSMutableArray *subs; @end
@implementation POFMesh @end

static NSString *Str(const uint8_t *b,NSUInteger n){ NSMutableString *m=[NSMutableString string]; for(NSUInteger i=0;i<n&&b[i];i++) if(b[i]>=32&&b[i]<127) [m appendFormat:@"%c",b[i]]; return m; }

static POFMesh *LoadPOFDetail0(NSString *path, NSString **err){ NSData *d=[NSData dataWithContentsOfFile:path]; if(!d||d.length<12){ if(err)*err=@"unreadable"; return nil;} const uint8_t *b=d.bytes; if(memcmp(b,"PSPO",4)!=0){ if(err)*err=@"bad signature"; return nil; }
    NSMutableArray *detail=[NSMutableArray array]; NSMutableDictionary *objById=[NSMutableDictionary dictionary]; NSMutableArray *textures=[NSMutableArray array];
    NSUInteger o=8; while(o+8<=d.length){ char id[5]={0}; memcpy(id,b+o,4); uint32_t len=U32(b+o+4); NSUInteger p=o+8; if(p+len>d.length) break;
        if(strcmp(id,"TXTR")==0){ NSUInteger i=0; while(i<len){ NSString *t=Str(b+p+i,len-i); if(t.length) [textures addObject:t]; i += t.length+1; } }
        if(strcmp(id,"HDR2")==0 && len>=12){ uint32_t nd=U32(b+p+8); NSUInteger q=p+12; for(uint32_t i=0;i<nd && q+4<=p+len;i++,q+=4) [detail addObject:@((int)U32(b+q))]; }
        if(strcmp(id,"OBJ2")==0 && len>=16){ POFSub *s=[POFSub new]; s.verts=[NSMutableData data]; s.tris=[NSMutableData data]; s.glow=[NSMutableData data]; s.sid=(int)U32(b+p); s.parent=(int)U32(b+p+4); s.spin=20; NSUInteger j=p+16; while(j+8<=p+len){ if(memcmp(b+j,"TXTR",4)==0){ uint32_t tl=U32(b+j+4); if(j+8+tl<=p+len) s.tex=Str(b+j+8,tl);} if(memcmp(b+j,"SPIN",4)==0){ s.rotates=YES; s.spin=F32(b+j+4);} if(memcmp(b+j,"D0V0",4)==0){ uint32_t c=U32(b+j+4); NSUInteger q=j+8; if(q+c*12<=p+len){ for(uint32_t k=0;k<c;k++){ V3 v={F32(b+q+k*12),F32(b+q+k*12+4),F32(b+q+k*12+8)}; [s.verts appendBytes:&v length:12]; } }} if(memcmp(b+j,"D0I0",4)==0){ uint32_t t=U32(b+j+4); NSUInteger q=j+8; if(q+t*6<=p+len) [s.tris appendBytes:b+q length:t*6]; } if(memcmp(b+j,"GPNT",4)==0){ uint32_t gc=U32(b+j+4); NSUInteger q=j+8; if(q+gc*12<=p+len) [s.glow appendBytes:b+q length:gc*12]; } j++; }
            if(!s.tex.length && textures.count) s.tex=textures[0]; objById[@(s.sid)]=s; }
        o=p+len;
    }
    POFMesh *m=[POFMesh new]; m.subs=[NSMutableArray array];
    if(detail.count>0){
        int root=(detail.count>1)?[detail[1] intValue]:[detail[0] intValue];
        for(NSNumber *k in objById){ POFSub *s=objById[k]; if(s.sid==root || s.parent==root || [detail containsObject:@(s.sid)]) [m.subs addObject:s]; }
        if(m.subs.count>0){ if(err)*err=[NSString stringWithFormat:@"lod1 subobjects=%lu",(unsigned long)m.subs.count]; return m; }
    }
    // Fallback when LOD1 is missing: use top-level models + direct submodels.
    int top=INT_MAX;
    for(NSNumber *k in objById){ POFSub *s=objById[k]; if(s.parent<0 && s.sid<top) top=s.sid; }
    for(NSNumber *k in objById){ POFSub *s=objById[k]; if(s.parent<0 || s.parent==top) [m.subs addObject:s]; }
    if(m.subs.count==0){ if(err)*err=@"no drawable subobjects"; return nil; }
    if(err)*err=[NSString stringWithFormat:@"lod1 missing, fallback subobjects=%lu",(unsigned long)m.subs.count]; return m;
}

static GLuint CheckerTexture(void){ unsigned char p[16]={255,255,255,255,20,20,20,255,20,20,20,255,255,255,255,255}; GLuint t; glGenTextures(1,&t); glBindTexture(GL_TEXTURE_2D,t); glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,2,2,0,GL_RGBA,GL_UNSIGNED_BYTE,p); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR); return t; }
static GLuint LoadTexture(NSString *p){ NSImage *i=[[NSImage alloc] initWithContentsOfFile:p]; if(!i) return CheckerTexture(); NSBitmapImageRep *r=nil; for(NSImageRep *x in i.representations) if([x isKindOfClass:[NSBitmapImageRep class]]) r=(NSBitmapImageRep*)x; if(!r) return CheckerTexture(); GLuint t; glGenTextures(1,&t); glBindTexture(GL_TEXTURE_2D,t); glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,r.pixelsWide,r.pixelsHigh,0,GL_RGBA,GL_UNSIGNED_BYTE,r.bitmapData); return t; }
static void DrawCube(float s){ float h=s/2; glBegin(GL_QUADS); glVertex3f(-h,-h,h);glVertex3f(h,-h,h);glVertex3f(h,h,h);glVertex3f(-h,h,h); glEnd(); }

@interface SpaceGLView : NSOpenGLView - (instancetype)initWithFrame:(NSRect)f scene:(SceneDefinition*)s; @end
@implementation SpaceGLView{ SceneDefinition *_s; NSTimer *_t; NSTimeInterval _last; float _e; NSMutableDictionary *_mesh,*_tex; NSMutableData *_stars; }
- (instancetype)initWithFrame:(NSRect)f scene:(SceneDefinition*)s{ NSOpenGLPixelFormatAttribute a[]={NSOpenGLPFADoubleBuffer,NSOpenGLPFAColorSize,24,NSOpenGLPFADepthSize,24,0}; if((self=[super initWithFrame:f pixelFormat:[[NSOpenGLPixelFormat alloc] initWithAttributes:a]])){ _s=s; _last=[NSDate timeIntervalSinceReferenceDate]; _mesh=[NSMutableDictionary dictionary]; _tex=[NSMutableDictionary dictionary]; _stars=[NSMutableData dataWithLength:sizeof(V3)*1500]; V3 *q=(V3*)_stars.mutableBytes; for(int i=0;i<1500;i++) q[i]=(V3){((float)arc4random()/UINT32_MAX-.5)*3000,((float)arc4random()/UINT32_MAX-.5)*3000,-((float)arc4random()/UINT32_MAX)*3000}; _t=[NSTimer scheduledTimerWithTimeInterval:1.0/60 target:self selector:@selector(onTick:) userInfo:nil repeats:YES]; } return self; }
- (void)onTick:(id)x{ (void)x; [self display]; } - (BOOL)acceptsFirstResponder{return YES;} - (void)keyDown:(NSEvent*)e{ if([[e charactersIgnoringModifiers] length]&&[[e charactersIgnoringModifiers] characterAtIndex:0]==27){ [NSApp terminate:nil]; return;} [super keyDown:e]; }
- (void)prepareOpenGL{ [super prepareOpenGL]; glEnable(GL_DEPTH_TEST);} - (void)reshape{ [super reshape]; NSRect b=self.bounds; glViewport(0,0,b.size.width,b.size.height); glMatrixMode(GL_PROJECTION); glLoadIdentity(); float asp=b.size.width/b.size.height,n=.1,f=6000,t=tanf(DegToRad(30))*n,r=t*asp; glFrustum(-r,r,-t,t,n,f);} 
- (void)drawRect:(NSRect)r{ (void)r; NSTimeInterval n=[NSDate timeIntervalSinceReferenceDate]; _e += (float)(n-_last); _last=n; glClearColor(.01,.01,.03,1); glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT); glMatrixMode(GL_MODELVIEW); glLoadIdentity(); glTranslatef(-_s.cameraPosition.x,-_s.cameraPosition.y,-_s.cameraPosition.z);
    if(!_s.skyboxName.length){ glDisable(GL_DEPTH_TEST); glPointSize(2); glBegin(GL_POINTS); V3 *st=(V3*)_stars.bytes; glColor3f(1,1,1); for(int i=0;i<1500;i++) glVertex3f(st[i].x,st[i].y,st[i].z); glEnd(); glEnable(GL_DEPTH_TEST);} 
    for(SceneModel *m in _s.models){ Vec3 p=m.position; if(m.hasOvalPath&&m.ovalRadius>0){ float a=DegToRad(m.ovalAngleOffset+_e*m.ovalSpeedDegPerSec); p.x+=cosf(a)*m.ovalRadius; p.z+=sinf(a)*m.ovalRadius;} glPushMatrix(); glTranslatef(p.x,p.y,p.z);
        POFMesh *pm=_mesh[m.pofPath]; if((id)pm==[NSNull null]) pm=nil; if(!pm && !_mesh[m.pofPath]){ NSString *e=nil; pm=LoadPOFDetail0(m.pofPath,&e); _mesh[m.pofPath]=pm?:[NSNull null]; NSLog(@"[POF] %@ -> %@",m.pofPath,e);} 
        if(pm){ glEnable(GL_TEXTURE_2D); for(POFSub *s in pm.subs){ NSString *tn=s.tex?:@""; NSNumber *ct=_tex[tn]; GLuint tx=ct?ct.unsignedIntValue:0; if(!tx){ NSString *base=[_s.textureRoot stringByAppendingPathComponent:tn]; NSString *fp=nil; for(NSString *e in @[@"png",@"dds",@"pcx"]){ NSString *p=[base stringByAppendingPathExtension:e]; if([[NSFileManager defaultManager] fileExistsAtPath:p]){ fp=p; break; }} tx=LoadTexture(fp?:base); _tex[tn]=@(tx); NSLog(@"[TEX] %@ -> %@",tn,fp?:@"fallback"); } glBindTexture(GL_TEXTURE_2D,tx); if(s.rotates){ glPushMatrix(); glRotatef(_e*s.spin,0,1,0);} const V3 *v=(const V3*)s.verts.bytes; const uint16_t *id=(const uint16_t*)s.tris.bytes; NSUInteger tc=s.tris.length/6; glBegin(GL_TRIANGLES); for(NSUInteger t=0;t<tc;t++)for(int k=0;k<3;k++){ uint16_t ii=id[t*3+k]; if(ii<s.verts.length/12){ V3 vv=v[ii]; glTexCoord2f((vv.x+50)/100,(vv.z+50)/100); glVertex3f(vv.x,vv.y,vv.z);} } glEnd(); if(s.rotates) glPopMatrix(); glDisable(GL_TEXTURE_2D); if(s.glow.length){ glPointSize(4); glColor3f(1,.7,.2); glBegin(GL_POINTS); const V3 *gp=(const V3*)s.glow.bytes; for(NSUInteger g=0;g<s.glow.length/12;g++) glVertex3f(gp[g].x,gp[g].y,gp[g].z); glEnd(); } }
        } else { glColor3f(1,.1,.1); DrawCube(12);} glPopMatrix();
    }
    [[self openGLContext] flushBuffer]; }
@end

int main(int argc,char **argv){ @autoreleasepool { NSString *sp=@"scene.txt"; if(argc>1) sp=[NSString stringWithUTF8String:argv[1]]; NSError *e=nil; SceneDefinition *s=[SceneParser parseSceneAtPath:sp error:&e]; if(!s){ fprintf(stderr,"scene load failed: %s\n",[[e description] UTF8String]); return 1;} [NSApplication sharedApplication]; NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,720) styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO]; SpaceGLView *v=[[SpaceGLView alloc] initWithFrame:NSMakeRect(0,0,1280,720) scene:s]; [w setContentView:v]; [w makeFirstResponder:v]; [w makeKeyAndOrderFront:nil]; [NSApp run]; } return 0; }
