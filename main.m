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
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error {
    NSString *raw=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error]; if(!raw) return nil;
    SceneDefinition *scene=[SceneDefinition new];
    for(NSString *lineRaw in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){
        NSString *line=[[[lineRaw componentsSeparatedByString:@"#"] objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if(!line.length) continue;
        NSRange eq=[line rangeOfString:@"="]; if(eq.location==NSNotFound) continue;
        NSString *key=[[[line substringToIndex:eq.location] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value=NormalizeScenePath([line substringFromIndex:eq.location+1]);
        if([key isEqualToString:@"camera"]){ NSArray *c=[value componentsSeparatedByString:@","]; if(c.count>=3) scene.cameraPosition=(Vec3){[c[0] floatValue],[c[1] floatValue],[c[2] floatValue]}; }
        else if([key isEqualToString:@"textureroot"]) scene.textureRoot=value;
        else if([key isEqualToString:@"skybox"]) scene.skyboxName=value.length?value:nil;
        else if([key isEqualToString:@"showloops"]) scene.showLoops=[[value lowercaseString] isEqualToString:@"true"];
        else if([key isEqualToString:@"model"]) {
            NSArray *chunks=[value componentsSeparatedByString:@","]; if(chunks.count<4) continue; SceneModel *m=[SceneModel new];
            m.pofPath=NormalizeScenePath(chunks[0]); m.position=(Vec3){[chunks[1] floatValue],[chunks[2] floatValue],[chunks[3] floatValue]};
            for(NSUInteger i=4;i<chunks.count;i++){ NSArray *kv=[[[chunks[i] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@"="]; if(kv.count!=2) continue;
                if([kv[0] isEqualToString:@"ovalpath"]) m.hasOvalPath=[kv[1] isEqualToString:@"true"]; else if([kv[0] isEqualToString:@"radius"]) m.ovalRadius=[kv[1] floatValue]; else if([kv[0] isEqualToString:@"speed"]) m.ovalSpeedDegPerSec=[kv[1] floatValue]; else if([kv[0] isEqualToString:@"offset"]) m.ovalAngleOffset=[kv[1] floatValue]; }
            [scene.models addObject:m];
        }
    }
    return scene;
}
@end

@interface TextureLoader : NSObject
+ (GLuint)loadTextureAtPath:(NSString *)path;
@end
@implementation TextureLoader
+ (GLuint)checkerTexture { unsigned char px[16]={255,255,255,255, 30,30,30,255, 30,30,30,255, 255,255,255,255}; GLuint t; glGenTextures(1,&t); glBindTexture(GL_TEXTURE_2D,t); glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,2,2,0,GL_RGBA,GL_UNSIGNED_BYTE,px); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR); return t; }
+ (GLuint)loadTextureAtPath:(NSString *)path {
    NSString *ext=[[path pathExtension] lowercaseString];
    if([ext isEqualToString:@"png"]) {
        NSImage *img=[[NSImage alloc] initWithContentsOfFile:path]; if(!img) return [self checkerTexture];
        NSBitmapImageRep *rep=nil; for(NSImageRep *r in [img representations]) if([r isKindOfClass:[NSBitmapImageRep class]]) { rep=(NSBitmapImageRep*)r; break; }
        if(!rep) return [self checkerTexture];
        GLuint tex; glGenTextures(1,&tex); glBindTexture(GL_TEXTURE_2D,tex);
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,(GLsizei)[rep pixelsWide],(GLsizei)[rep pixelsHigh],0,GL_RGBA,GL_UNSIGNED_BYTE,[rep bitmapData]);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR); return tex;
    }
    // .dds and .pcx accepted inputs; fallback texture generated if decoder unavailable.
    if([ext isEqualToString:@"dds"] || [ext isEqualToString:@"pcx"]) return [self checkerTexture];
    return [self checkerTexture];
}
@end

static void DrawCube(float s){ float h=s*0.5f; glBegin(GL_QUADS);
#define V(a,b,c) glVertex3f(a,b,c)
V(-h,-h,h);V(h,-h,h);V(h,h,h);V(-h,h,h); V(-h,-h,-h);V(-h,h,-h);V(h,h,-h);V(h,-h,-h);
V(-h,h,-h);V(-h,h,h);V(h,h,h);V(h,h,-h); V(-h,-h,-h);V(h,-h,-h);V(h,-h,h);V(-h,-h,h);
V(h,-h,-h);V(h,h,-h);V(h,h,h);V(h,-h,h); V(-h,-h,-h);V(-h,-h,h);V(-h,h,h);V(-h,h,-h);
#undef V
glEnd(); }


static BOOL LoadPOFDetail0(NSString *pofPath, NSString **errorMessage) {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:pofPath isDirectory:&isDir] || isDir) {
        if (errorMessage) *errorMessage = @"POF file not found";
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfFile:pofPath];
    if (!data || [data length] < 4) {
        if (errorMessage) *errorMessage = @"POF file is unreadable or too small";
        return NO;
    }
    const char *bytes = (const char *)[data bytes];
    if (!(bytes[0]=='P' && bytes[1]=='S' && bytes[2]=='P' && bytes[3]=='O')) {
        if (errorMessage) *errorMessage = @"POF header signature mismatch";
        return NO;
    }
    if (errorMessage) *errorMessage = @"POF parsed header OK; detail0 mesh decode not implemented yet";
    return NO;
}

@interface SpaceGLView : NSOpenGLView
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene;
@end
@implementation SpaceGLView { SceneDefinition *_scene; NSTimer *_timer; NSTimeInterval _last; float _elapsed; NSMutableSet *_loggedPOFs; }
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene { NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFADoubleBuffer,NSOpenGLPFAColorSize,24,NSOpenGLPFADepthSize,24,0}; if((self=[super initWithFrame:frame pixelFormat:[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs]])){ _scene=scene; _last=[NSDate timeIntervalSinceReferenceDate]; _timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(onTick:) userInfo:nil repeats:YES]; _loggedPOFs=[NSMutableSet set]; } return self; }
- (void)onTick:(NSTimer*)t { (void)t; [self display]; }
- (void)prepareOpenGL { [super prepareOpenGL]; glEnable(GL_DEPTH_TEST); }
- (void)reshape { [super reshape]; NSRect b=[self bounds]; glViewport(0,0,b.size.width,b.size.height); glMatrixMode(GL_PROJECTION); glLoadIdentity(); float asp=b.size.height>0?b.size.width/b.size.height:1; float n=.1f,f=5000.f,top=tanf(DegToRad(30))*n,right=top*asp; glFrustum(-right,right,-top,top,n,f); }
- (void)drawRect:(NSRect)r { (void)r; NSTimeInterval n=[NSDate timeIntervalSinceReferenceDate]; _elapsed += (float)(n-_last); _last=n; glClearColor(0.01,0.01,0.03,1); glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT); glMatrixMode(GL_MODELVIEW); glLoadIdentity(); glTranslatef(-_scene.cameraPosition.x,-_scene.cameraPosition.y,-_scene.cameraPosition.z);
    for(SceneModel *m in _scene.models){ Vec3 p=m.position; if(m.hasOvalPath&&m.ovalRadius>0){ float a=DegToRad(m.ovalAngleOffset+_elapsed*m.ovalSpeedDegPerSec); p.x+=cosf(a)*m.ovalRadius; p.z+=sinf(a)*m.ovalRadius; }
        glPushMatrix(); glTranslatef(p.x,p.y,p.z); NSString *pofError=nil; BOOL found=LoadPOFDetail0(m.pofPath,&pofError);
        if(![_loggedPOFs containsObject:m.pofPath]){
            if(!found){ NSLog(@"[POF] FAILED %@ -> %@", m.pofPath, pofError); }
            else { NSLog(@"[POF] LOADED detail0 %@", m.pofPath); }
            [_loggedPOFs addObject:m.pofPath];
        }
        glColor3f(found?0.6:1.0,found?0.8:0.1,found?1.0:0.1); DrawCube(found?8.f:12.f); glPopMatrix();
        if(_scene.showLoops && m.hasOvalPath && m.ovalRadius>0){ glColor3f(1,0,0); glLineWidth(3); glBegin(GL_LINE_LOOP); for(int i=0;i<96;i++){ float a=DegToRad(360.f*i/96.f); glVertex3f(m.position.x+cosf(a)*m.ovalRadius,m.position.y,m.position.z+sinf(a)*m.ovalRadius);} glEnd(); }
    }
    [[self openGLContext] flushBuffer]; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] > 0 && [chars characterAtIndex:0] == 27) {
        [NSApp terminate:nil];
        return;
    }
    [super keyDown:event];
}
@end

int main(int argc,char **argv){ NSAutoreleasePool *pool=[NSAutoreleasePool new]; NSString *scenePath=@"scene.txt"; if(argc>1) scenePath=[NSString stringWithUTF8String:argv[1]]; NSError *err=nil; SceneDefinition *scene=[SceneParser parseSceneAtPath:scenePath error:&err]; if(!scene){ fprintf(stderr,"scene load failed: %s\n",[[err description] UTF8String]); return 1; } [NSApplication sharedApplication]; NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,720) styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO]; [w setTitle:@"3D Scene Viewer (GNUstep)"]; [w setContentView:[[SpaceGLView alloc] initWithFrame:NSMakeRect(0,0,1280,720) scene:scene]]; [w makeKeyAndOrderFront:nil]; [NSApp run]; [pool drain]; return 0; }
