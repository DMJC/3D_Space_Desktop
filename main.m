#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GL/gl.h>
#import <math.h>

typedef struct { float x, y, z; } Vec3;
static inline float DegToRad(float d){ return d*(float)M_PI/180.f; }

static NSString *NormalizeScenePath(NSString *raw) {
    return [[raw stringByReplacingOccurrencesOfString:@"\\ " withString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@interface SceneModel : NSObject
@property(nonatomic, copy) NSString *pofPath;
@property(nonatomic) Vec3 position;
@property(nonatomic) BOOL hasOvalPath;
@property(nonatomic) float ovalRadius;
@property(nonatomic) float ovalSpeedDegPerSec;
@property(nonatomic) float ovalAngleOffset;
@end
@implementation SceneModel @end

@interface SceneDefinition : NSObject
@property(nonatomic) Vec3 cameraPosition;
@property(nonatomic, copy) NSString *textureRoot;
@property(nonatomic, copy) NSString *skyboxName;
@property(nonatomic) BOOL showLoops;
@property(nonatomic, strong) NSMutableArray *models;
@end
@implementation SceneDefinition
- (instancetype)init { if((self=[super init])){ _cameraPosition=(Vec3){0,0,30}; _showLoops=NO; _models=[NSMutableArray array]; } return self; }
@end

@interface SceneParser : NSObject
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error;
@end
@implementation SceneParser
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error {
    NSString *raw=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if(!raw) return nil;
    SceneDefinition *scene=[SceneDefinition new];
    for(NSString *lineRaw in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line=[[[lineRaw componentsSeparatedByString:@"#"] objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if([line length]==0) continue;
        NSRange eq=[line rangeOfString:@"="]; if(eq.location==NSNotFound) continue;
        NSString *key=[[[line substringToIndex:eq.location] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value=NormalizeScenePath([line substringFromIndex:eq.location+1]);
        if([key isEqualToString:@"camera"]) {
            NSArray *c=[value componentsSeparatedByString:@","]; if([c count]>=3) scene.cameraPosition=(Vec3){[[c objectAtIndex:0] floatValue],[[c objectAtIndex:1] floatValue],[[c objectAtIndex:2] floatValue]};
        } else if([key isEqualToString:@"textureroot"]) scene.textureRoot=value;
        else if([key isEqualToString:@"skybox"]) scene.skyboxName=([value length]?value:nil);
        else if([key isEqualToString:@"showloops"]) scene.showLoops=[[value lowercaseString] isEqualToString:@"true"];
        else if([key isEqualToString:@"model"]) {
            NSArray *chunks=[value componentsSeparatedByString:@","]; if([chunks count]>=4) {
                SceneModel *m=[SceneModel new];
                m.pofPath=NormalizeScenePath([chunks objectAtIndex:0]);
                m.position=(Vec3){[[chunks objectAtIndex:1] floatValue],[[chunks objectAtIndex:2] floatValue],[[chunks objectAtIndex:3] floatValue]};
                for(NSUInteger i=4;i<[chunks count];i++) {
                    NSString *opt=[[[chunks objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
                    NSArray *kv=[opt componentsSeparatedByString:@"="]; if([kv count]!=2) continue;
                    NSString *ok=[kv objectAtIndex:0], *ov=[kv objectAtIndex:1];
                    if([ok isEqualToString:@"ovalpath"]) m.hasOvalPath=[ov isEqualToString:@"true"];
                    else if([ok isEqualToString:@"radius"]) m.ovalRadius=[ov floatValue];
                    else if([ok isEqualToString:@"speed"]) m.ovalSpeedDegPerSec=[ov floatValue];
                    else if([ok isEqualToString:@"offset"]) m.ovalAngleOffset=[ov floatValue];
                }
                [scene.models addObject:m];
            }
        }
    }
    return scene;
}
@end

static void DrawCube(float s) {
    float h=s*0.5f;
    glBegin(GL_QUADS);
    glVertex3f(-h,-h,h); glVertex3f(h,-h,h); glVertex3f(h,h,h); glVertex3f(-h,h,h);
    glVertex3f(-h,-h,-h); glVertex3f(-h,h,-h); glVertex3f(h,h,-h); glVertex3f(h,-h,-h);
    glVertex3f(-h,h,-h); glVertex3f(-h,h,h); glVertex3f(h,h,h); glVertex3f(h,h,-h);
    glVertex3f(-h,-h,-h); glVertex3f(h,-h,-h); glVertex3f(h,-h,h); glVertex3f(-h,-h,h);
    glVertex3f(h,-h,-h); glVertex3f(h,h,-h); glVertex3f(h,h,h); glVertex3f(h,-h,h);
    glVertex3f(-h,-h,-h); glVertex3f(-h,-h,h); glVertex3f(-h,h,h); glVertex3f(-h,h,-h);
    glEnd();
}

@interface SpaceGLView : NSOpenGLView
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene;
@end
@implementation SpaceGLView { SceneDefinition *_scene; NSTimer *_timer; NSTimeInterval _lastTime; float _elapsed; }
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene {
    NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFADoubleBuffer,NSOpenGLPFAColorSize,24,NSOpenGLPFADepthSize,24,0};
    NSOpenGLPixelFormat *pf=[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if((self=[super initWithFrame:frame pixelFormat:pf])){ _scene=scene; _lastTime=[NSDate timeIntervalSinceReferenceDate]; _timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(onTick:) userInfo:nil repeats:YES]; }
    return self;
}
- (void)onTick:(NSTimer *)t { (void)t; [self display]; }
- (void)prepareOpenGL { [super prepareOpenGL]; glEnable(GL_DEPTH_TEST); }
- (void)reshape {
    [super reshape]; NSRect b=[self bounds];
    glViewport(0,0,(GLsizei)b.size.width,(GLsizei)b.size.height);
    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    float aspect=(b.size.height>0)?(b.size.width/b.size.height):1.f;
    float fov=60.f, near=0.1f, far=5000.f, top=tanf(DegToRad(fov*0.5f))*near, right=top*aspect;
    glFrustum(-right,right,-top,top,near,far);
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate]; _elapsed += (float)(now-_lastTime); _lastTime=now;
    if([_scene.skyboxName length]>0) glClearColor(0.02f,0.02f,0.08f,1.f); else glClearColor(0,0,0,1);
    glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glTranslatef(-_scene.cameraPosition.x,-_scene.cameraPosition.y,-_scene.cameraPosition.z);
    for(SceneModel *m in _scene.models){
        Vec3 p=m.position;
        if(m.hasOvalPath && m.ovalRadius>0){ float a=DegToRad(m.ovalAngleOffset+_elapsed*m.ovalSpeedDegPerSec); p.x += cosf(a)*m.ovalRadius; p.z += sinf(a)*m.ovalRadius; }
        glPushMatrix(); glTranslatef(p.x,p.y,p.z);
        BOOL found=[[NSFileManager defaultManager] fileExistsAtPath:m.pofPath];
        if(found) glColor3f(0.6f,0.7f,1.f); else glColor3f(1.f,0.1f,0.1f);
        DrawCube(found?8.f:12.f);
        glPopMatrix();

        if(_scene.showLoops && m.hasOvalPath && m.ovalRadius>0){
            glColor3f(1,0,0); glLineWidth(3.f); glBegin(GL_LINE_LOOP);
            for(int i=0;i<96;i++){ float a=DegToRad((360.f*i)/96.f); glVertex3f(m.position.x+cosf(a)*m.ovalRadius,m.position.y,m.position.z+sinf(a)*m.ovalRadius);} glEnd();
        }
    }
    [[self openGLContext] flushBuffer];
}
@end

int main(int argc, char **argv){
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSString *scenePath=@"scene.txt"; if(argc>1) scenePath=[NSString stringWithUTF8String:argv[1]];
    NSError *error=nil; SceneDefinition *scene=[SceneParser parseSceneAtPath:scenePath error:&error];
    if(!scene){ fprintf(stderr,"Failed to load scene file: %s\n", [[error description] UTF8String]); [pool drain]; return 1; }
    [NSApplication sharedApplication];
    NSRect frame=NSMakeRect(0,0,1280,720);
    NSWindow *window=[[NSWindow alloc] initWithContentRect:frame styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"3D Scene Viewer (GNUstep)"];
    SpaceGLView *view=[[SpaceGLView alloc] initWithFrame:frame scene:scene];
    [window setContentView:view]; [window makeKeyAndOrderFront:nil];
    [NSApp run]; [pool drain]; return 0;
}
