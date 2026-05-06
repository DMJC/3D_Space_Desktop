#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <GLKit/GLKit.h>

#pragma mark - Scene Data Types

typedef struct {
    float x;
    float y;
    float z;
} Vec3;

@interface SceneModel : NSObject
@property(nonatomic, copy) NSString *pofPath;
@property(nonatomic, assign) Vec3 position;
@property(nonatomic, assign) BOOL hasOvalPath;
@property(nonatomic, assign) float ovalRadius;
@property(nonatomic, assign) float ovalSpeedDegPerSec;
@property(nonatomic, assign) float ovalAngleOffset;
@end

@implementation SceneModel
@end

@interface SceneDefinition : NSObject
@property(nonatomic, assign) Vec3 cameraPosition;
@property(nonatomic, copy) NSString *textureRoot;
@property(nonatomic, copy) NSString *skyboxName;
@property(nonatomic, assign) BOOL showLoops;
@property(nonatomic, strong) NSMutableArray<SceneModel *> *models;
@end

@implementation SceneDefinition
- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraPosition = (Vec3){0, 0, 30};
        _showLoops = NO;
        _models = [NSMutableArray array];
    }
    return self;
}
@end

#pragma mark - Parser

@interface SceneParser : NSObject
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error;
@end

@implementation SceneParser
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error {
    NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!raw) return nil;

    SceneDefinition *scene = [[SceneDefinition alloc] init];
    NSArray<NSString *> *lines = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSString *lineRaw in lines) {
        NSString *line = [[lineRaw componentsSeparatedByString:@"#"].firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0) continue;

        NSArray<NSString *> *parts = [line componentsSeparatedByString:@"="];
        if (parts.count < 2) continue;

        NSString *key = [parts[0].lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"="];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        if ([key isEqualToString:@"camera"]) {
            NSArray *c = [value componentsSeparatedByString:@","];
            if (c.count >= 3) {
                scene.cameraPosition = (Vec3){c[0].floatValue, c[1].floatValue, c[2].floatValue};
            }
        } else if ([key isEqualToString:@"textureroot"]) {
            scene.textureRoot = value;
        } else if ([key isEqualToString:@"skybox"]) {
            scene.skyboxName = value.length ? value : nil;
        } else if ([key isEqualToString:@"showloops"]) {
            scene.showLoops = [value.lowercaseString isEqualToString:@"true"];
        } else if ([key isEqualToString:@"model"]) {
            // model=pofPath,x,y,z[,ovalpath=true,radius=20,speed=30,offset=45]
            NSArray *chunks = [value componentsSeparatedByString:@","];
            if (chunks.count >= 4) {
                SceneModel *m = [[SceneModel alloc] init];
                m.pofPath = [chunks[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                m.position = (Vec3){chunks[1].floatValue, chunks[2].floatValue, chunks[3].floatValue};
                for (NSUInteger i = 4; i < chunks.count; i++) {
                    NSString *opt = [chunks[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
                    NSArray *kv = [opt componentsSeparatedByString:@"="];
                    if (kv.count != 2) continue;
                    NSString *ok = kv[0];
                    NSString *ov = kv[1];
                    if ([ok isEqualToString:@"ovalpath"]) m.hasOvalPath = [ov isEqualToString:@"true"];
                    if ([ok isEqualToString:@"radius"]) m.ovalRadius = ov.floatValue;
                    if ([ok isEqualToString:@"speed"]) m.ovalSpeedDegPerSec = ov.floatValue;
                    if ([ok isEqualToString:@"offset"]) m.ovalAngleOffset = ov.floatValue;
                }
                [scene.models addObject:m];
            }
        }
    }

    return scene;
}
@end

#pragma mark - Renderer

@interface SpaceGLView : NSOpenGLView
- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene;
@end

@implementation SpaceGLView {
    SceneDefinition *_scene;
    NSTimer *_timer;
    NSTimeInterval _lastTime;
    float _elapsed;
}

- (instancetype)initWithFrame:(NSRect)frame scene:(SceneDefinition *)scene {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        0
    };
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    self = [super initWithFrame:frame pixelFormat:pf];
    if (self) {
        _scene = scene;
        _lastTime = [NSDate date].timeIntervalSince1970;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [self setNeedsDisplay:YES];
        }];
    }
    return self;
}

- (void)prepareOpenGL {
    [super prepareOpenGL];
    glEnable(GL_DEPTH_TEST);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    _elapsed += (float)(now - _lastTime);
    _lastTime = now;

    if (_scene.skyboxName.length > 0) {
        glClearColor(0.02f, 0.02f, 0.08f, 1.0f);
    } else {
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    }
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // Placeholder rendering pass. Real app should upload meshes from POF detail level 0 and texture DDS/PNG/PCX.
    for (SceneModel *m in _scene.models) {
        Vec3 p = m.position;
        if (m.hasOvalPath && m.ovalRadius > 0.0f) {
            float angle = GLKMathDegreesToRadians(m.ovalAngleOffset + _elapsed * m.ovalSpeedDegPerSec);
            p.x += cosf(angle) * m.ovalRadius;
            p.z += sinf(angle) * m.ovalRadius;
        }

        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:m.pofPath];
        if (!fileExists) {
            // Missing POF: draw red cube placeholder.
            // Stub in core profile: visually represented by clear tint change for this sample.
            glClearColor(0.2f, 0.0f, 0.0f, 1.0f);
        }

        if (_scene.showLoops && m.hasOvalPath && m.ovalRadius > 0) {
            glLineWidth(3.0f);
            // Loop path rendering would draw a red circle polyline in world-space.
        }
        (void)p;
    }

    [[self openGLContext] flushBuffer];
}
@end

#pragma mark - App bootstrap

static NSString *SceneFormatHelp(void) {
    return @"scene.txt format:\n"
            @"camera=x,y,z\n"
            @"textureRoot=/path/to/textures\n"
            @"skybox=skybox_name   # optional, loads skybox_name01..06\n"
            @"showLoops=true|false\n"
            @"model=/path/to/model.pof,x,y,z[,ovalpath=true,radius=30,speed=40,offset=0]\n";
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *scenePath = @"scene.txt";
        if (argc > 1) {
            scenePath = [NSString stringWithUTF8String:argv[1]];
        }

        NSError *error = nil;
        SceneDefinition *scene = [SceneParser parseSceneAtPath:scenePath error:&error];
        if (!scene) {
            fprintf(stderr, "Failed to load scene file '%s'\n%s\n", scenePath.UTF8String, SceneFormatHelp().UTF8String);
            if (error) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, 1280, 720);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        window.title = @"3D Scene Viewer";

        SpaceGLView *glView = [[SpaceGLView alloc] initWithFrame:frame scene:scene];
        window.contentView = glView;
        [window makeKeyAndOrderFront:nil];
        [NSApp run];
    }
    return 0;
}
