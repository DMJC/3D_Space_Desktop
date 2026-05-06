#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#ifdef __APPLE__
#import <OpenGL/gl3.h>
#else
#import <GL/gl.h>
#endif
#import <math.h>

typedef struct { float x, y, z; } Vec3;

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
    NSArray *lines=[raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSEnumerator *en=[lines objectEnumerator]; NSString *lineRaw=nil;
    while((lineRaw=[en nextObject])) {
        NSString *line=[[[lineRaw componentsSeparatedByString:@"#"] objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if([line length]==0) continue;
        NSRange eq=[line rangeOfString:@"="]; if(eq.location==NSNotFound) continue;
        NSString *key=[[[line substringToIndex:eq.location] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value=[[line substringFromIndex:eq.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if([key isEqualToString:@"camera"]) {
            NSArray *c=[value componentsSeparatedByString:@","]; if([c count]>=3) scene.cameraPosition=(Vec3){[[c objectAtIndex:0] floatValue],[[c objectAtIndex:1] floatValue],[[c objectAtIndex:2] floatValue]};
        } else if([key isEqualToString:@"textureroot"]) scene.textureRoot=value;
        else if([key isEqualToString:@"skybox"]) scene.skyboxName=([value length]?value:nil);
        else if([key isEqualToString:@"showloops"]) scene.showLoops=[[value lowercaseString] isEqualToString:@"true"];
        else if([key isEqualToString:@"model"]) {
            NSArray *chunks=[value componentsSeparatedByString:@","]; if([chunks count]>=4) {
                SceneModel *m=[SceneModel new];
                m.pofPath=[[chunks objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                m.position=(Vec3){[[chunks objectAtIndex:1] floatValue],[[chunks objectAtIndex:2] floatValue],[[chunks objectAtIndex:3] floatValue]};
                NSUInteger i; for(i=4;i<[chunks count];i++) {
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

@interface SpaceGLView : NSOpenGLView
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene;
@end

@implementation SpaceGLView {
    SceneDefinition *_scene; NSTimer *_timer; NSTimeInterval _lastTime; float _elapsed;
}
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene {
    NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFADoubleBuffer, NSOpenGLPFAColorSize,24, NSOpenGLPFADepthSize,24, 0};
    NSOpenGLPixelFormat *pf=[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if((self=[super initWithFrame:frame pixelFormat:pf])) {
        _scene=scene; _lastTime=[NSDate timeIntervalSinceReferenceDate];
        _timer=[NSTimer scheduledTimerWithTimeInterval:(1.0/60.0) target:self selector:@selector(onTick:) userInfo:nil repeats:YES];
    }
    return self;
}
- (void)onTick:(NSTimer *)t { (void)t; [self setNeedsDisplay:YES]; }
- (void)prepareOpenGL { [super prepareOpenGL]; glEnable(GL_DEPTH_TEST); }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate]; _elapsed += (float)(now-_lastTime); _lastTime=now;
    if([_scene.skyboxName length]>0) glClearColor(0.02f,0.02f,0.08f,1.f); else glClearColor(0,0,0,1);
    glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
    NSEnumerator *en=[_scene.models objectEnumerator]; SceneModel *m=nil;
    while((m=[en nextObject])) {
        Vec3 p=m.position;
        if(m.hasOvalPath && m.ovalRadius>0){ float angle=(m.ovalAngleOffset + _elapsed*m.ovalSpeedDegPerSec)*(float)M_PI/180.f; p.x += cosf(angle)*m.ovalRadius; p.z += sinf(angle)*m.ovalRadius; }
        if(![[NSFileManager defaultManager] fileExistsAtPath:m.pofPath]) { glClearColor(0.2f,0,0,1); }
        if(_scene.showLoops && m.hasOvalPath && m.ovalRadius>0) glLineWidth(3.f);
        (void)p;
    }
    [[self openGLContext] flushBuffer];
}
@end

int main(int argc, char **argv) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSString *scenePath=@"scene.txt"; if(argc>1) scenePath=[NSString stringWithUTF8String:argv[1]];
    NSError *error=nil; SceneDefinition *scene=[SceneParser parseSceneAtPath:scenePath error:&error];
    if(!scene){ fprintf(stderr,"Failed to load scene.txt: %s\n", [[error description] UTF8String]); [pool drain]; return 1; }

    [NSApplication sharedApplication];
    NSRect frame=NSMakeRect(0,0,1280,720);
    NSWindow *window=[[NSWindow alloc] initWithContentRect:frame styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"3D Scene Viewer (GNUstep)"];
    SpaceGLView *view=[[SpaceGLView alloc] initWithFrame:frame scene:scene];
    [window setContentView:view]; [window makeKeyAndOrderFront:nil];
    [NSApp run];
    [pool drain];
    return 0;
}
