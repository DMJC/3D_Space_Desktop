#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GL/glew.h>
#import <math.h>
#import <stdint.h>
#import <string.h>
#import <limits.h>

typedef struct { float x, y, z; } Vec3;
typedef struct { float x, y, z; } V3;

#define VIEW_FOV_Y_DEG 75.0f
#define VIEW_NEAR_PLANE 1.0f
#define VIEW_FAR_PLANE 50000.0f

static inline float DegToRad(float d)
{
    return d * (float)M_PI / 180.0f;
}

static inline Vec3 V3Normalize(Vec3 v)
{
    float len = sqrtf(v.x*v.x + v.y*v.y + v.z*v.z);
    if(len < 1e-6f) return (Vec3){0, 1, 0};
    return (Vec3){v.x/len, v.y/len, v.z/len};
}

static inline Vec3 V3Cross(Vec3 a, Vec3 b)
{
    return (Vec3){a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x};
}

static inline Vec3 V3RotX(Vec3 v, float deg)
{
    float c = cosf(DegToRad(deg)), s = sinf(DegToRad(deg));
    return (Vec3){v.x, v.y*c - v.z*s, v.y*s + v.z*c};
}

static inline Vec3 V3RotY(Vec3 v, float deg)
{
    float c = cosf(DegToRad(deg)), s = sinf(DegToRad(deg));
    return (Vec3){v.x*c + v.z*s, v.y, -v.x*s + v.z*c};
}

static inline Vec3 V3RotZ(Vec3 v, float deg)
{
    float c = cosf(DegToRad(deg)), s = sinf(DegToRad(deg));
    return (Vec3){v.x*c - v.y*s, v.x*s + v.y*c, v.z};
}

static inline Vec3 V3RotXYZ(Vec3 v, Vec3 euler)
{
    return V3RotZ(V3RotY(V3RotX(v, euler.x), euler.y), euler.z);
}

// Column-major 4x4 float matrix (OpenGL convention)
typedef struct { float m[16]; } Mat4;

static inline Mat4 Mat4Identity(void)
{
    Mat4 r = {{0}};
    r.m[0] = r.m[5] = r.m[10] = r.m[15] = 1.0f;
    return r;
}

static inline Mat4 Mat4Mul(Mat4 a, Mat4 b)
{
    Mat4 r;
    for(int c = 0; c < 4; c++)
        for(int row = 0; row < 4; row++)
        {
            float s = 0;
            for(int k = 0; k < 4; k++)
                s += a.m[k*4+row] * b.m[c*4+k];
            r.m[c*4+row] = s;
        }
    return r;
}

static inline Mat4 Mat4Translate(float x, float y, float z)
{
    Mat4 r = Mat4Identity();
    r.m[12] = x; r.m[13] = y; r.m[14] = z;
    return r;
}

static inline Mat4 Mat4RotateX(float deg)
{
    float c = cosf(DegToRad(deg)), s = sinf(DegToRad(deg));
    Mat4 r = Mat4Identity();
    r.m[5] = c; r.m[6] = s; r.m[9] = -s; r.m[10] = c;
    return r;
}

static inline Mat4 Mat4RotateY(float deg)
{
    float c = cosf(DegToRad(deg)), s = sinf(DegToRad(deg));
    Mat4 r = Mat4Identity();
    r.m[0] = c; r.m[2] = -s; r.m[8] = s; r.m[10] = c;
    return r;
}

static inline Mat4 Mat4RotateZ(float deg)
{
    float c = cosf(DegToRad(deg)), s = sinf(DegToRad(deg));
    Mat4 r = Mat4Identity();
    r.m[0] = c; r.m[1] = s; r.m[4] = -s; r.m[5] = c;
    return r;
}

static inline Mat4 Mat4Frustum(float l, float ri, float b, float t, float n, float f)
{
    Mat4 mat = {{0}};
    mat.m[0]  = 2.0f*n/(ri-l);
    mat.m[5]  = 2.0f*n/(t-b);
    mat.m[8]  = (ri+l)/(ri-l);
    mat.m[9]  = (t+b)/(t-b);
    mat.m[10] = -(f+n)/(f-n);
    mat.m[11] = -1.0f;
    mat.m[14] = -2.0f*f*n/(f-n);
    return mat;
}

static NSString *NormalizeScenePath(NSString *raw)
{
    return [[raw stringByReplacingOccurrencesOfString:@"\\\\ " withString:@" "]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static uint32_t U32(const uint8_t *p)
{
    return ((uint32_t)p[0]) |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint16_t U16(const uint8_t *p)
{
    return ((uint16_t)p[0]) |
           ((uint16_t)p[1] << 8);
}

static float F32(const uint8_t *p)
{
    float f;
    memcpy(&f, p, sizeof(float));
    return f;
}

static NSString *FourCCString(const uint8_t *p)
{
    char s[5] = {0};
    memcpy(s, p, 4);
    return [NSString stringWithUTF8String:s];
}

static NSString *Str(const uint8_t *b, NSUInteger n)
{
    NSMutableString *m = [NSMutableString string];

    for(NSUInteger i = 0; i < n && b[i]; i++)
    {
        if(b[i] >= 32 && b[i] < 127)
            [m appendFormat:@"%c", b[i]];
    }

    return m;
}

@interface SceneModel : NSObject
@property(nonatomic, copy) NSString *pofPath;
@property(nonatomic) Vec3 position;
@property(nonatomic) Vec3 rotationDeg;
@property(nonatomic) BOOL hasOvalPath;
@property(nonatomic) float ovalRadius;
@property(nonatomic) float ovalSpeedDegPerSec;
@property(nonatomic) float ovalAngleOffset;
@property(nonatomic) Vec3 ovalPlaneRot;
@property(nonatomic) BOOL ovalRev;
@property(nonatomic) BOOL rotSync;
@property(nonatomic) BOOL rotRev;
@end

@implementation SceneModel
@end

@interface SceneDefinition : NSObject
@property(nonatomic) Vec3 cameraPosition;
@property(nonatomic, copy) NSString *textureRoot;
@property(nonatomic, copy) NSString *skyboxName;
@property(nonatomic) BOOL showLoops;
@property(nonatomic, strong) NSMutableArray *models;
@property(nonatomic) Vec3 sunDir;  // normalized direction FROM scene TOWARD sun
@end

@implementation SceneDefinition
- (instancetype)init
{
    if((self = [super init]))
    {
        _cameraPosition = (Vec3){0, 0, 8000};
        _models = [NSMutableArray array];
        _sunDir = V3Normalize((Vec3){1, 1, 1});
    }

    return self;
}
@end

@interface SceneParser : NSObject
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error;
@end

@implementation SceneParser
+ (SceneDefinition *)parseSceneAtPath:(NSString *)path error:(NSError **)error
{
    NSString *raw = [NSString stringWithContentsOfFile:path
                                              encoding:NSUTF8StringEncoding
                                                 error:error];
    if(!raw)
        return nil;

    SceneDefinition *s = [SceneDefinition new];
    NSString *sceneDir = [path stringByDeletingLastPathComponent];

    for(NSString *lr in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        NSString *line = [[[[lr componentsSeparatedByString:@"#"] objectAtIndex:0]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] copy];

        if(!line.length)
            continue;

        NSRange eq = [line rangeOfString:@"="];
        if(eq.location == NSNotFound)
            continue;

        NSString *k = [[[line substringToIndex:eq.location] lowercaseString]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *v = NormalizeScenePath([line substringFromIndex:eq.location + 1]);

        if([k isEqualToString:@"camera"])
        {
            NSArray *c = [v componentsSeparatedByString:@","];
            if(c.count >= 3)
            {
                s.cameraPosition = (Vec3){[c[0] floatValue], [c[1] floatValue], [c[2] floatValue]};
            }
        }
        else if([k isEqualToString:@"textureroot"])
        {
            if([v isAbsolutePath])
                s.textureRoot = v;
            else
                s.textureRoot = [sceneDir stringByAppendingPathComponent:v];
        }
        else if([k isEqualToString:@"skybox"])
        {
            s.skyboxName = v.length ? v : nil;
        }
        else if([k isEqualToString:@"showloops"])
        {
            s.showLoops = [[v lowercaseString] isEqualToString:@"true"];
        }
        else if([k isEqualToString:@"sun"])
        {
            NSArray *c = [v componentsSeparatedByString:@","];
            if(c.count >= 3)
            {
                Vec3 d = {[c[0] floatValue], [c[1] floatValue], [c[2] floatValue]};
                float len = sqrtf(d.x*d.x + d.y*d.y + d.z*d.z);
                if(len > 0.0f)
                    s.sunDir = (Vec3){d.x/len, d.y/len, d.z/len};
            }
        }
        else if([k isEqualToString:@"model"])
        {
            NSArray *ch = [v componentsSeparatedByString:@","];
            if(ch.count < 4)
                continue;

            SceneModel *m = [SceneModel new];
            NSString *modelPath = NormalizeScenePath(ch[0]);

            if([modelPath isAbsolutePath])
                m.pofPath = modelPath;
            else
                m.pofPath = [sceneDir stringByAppendingPathComponent:modelPath];

            m.position = (Vec3){[ch[1] floatValue], [ch[2] floatValue], [ch[3] floatValue]};

            for(NSUInteger i = 4; i < ch.count; i++)
            {
                NSString *item = [[[ch[i] lowercaseString]
                                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] copy];
                NSArray *kv = [item componentsSeparatedByString:@"="];
                if(kv.count != 2)
                    continue;

                if([kv[0] isEqualToString:@"ovalpath"])
                    m.hasOvalPath = [kv[1] isEqualToString:@"true"];
                else if([kv[0] isEqualToString:@"radius"])
                    m.ovalRadius = [kv[1] floatValue];
                else if([kv[0] isEqualToString:@"speed"])
                    m.ovalSpeedDegPerSec = [kv[1] floatValue];
                else if([kv[0] isEqualToString:@"offset"])
                    m.ovalAngleOffset = [kv[1] floatValue];
                else if([kv[0] isEqualToString:@"rotx"])
                    m.rotationDeg = (Vec3){[kv[1] floatValue], m.rotationDeg.y, m.rotationDeg.z};
                else if([kv[0] isEqualToString:@"roty"])
                    m.rotationDeg = (Vec3){m.rotationDeg.x, [kv[1] floatValue], m.rotationDeg.z};
                else if([kv[0] isEqualToString:@"rotz"])
                    m.rotationDeg = (Vec3){m.rotationDeg.x, m.rotationDeg.y, [kv[1] floatValue]};
                else if([kv[0] isEqualToString:@"ovalrotx"])
                    m.ovalPlaneRot = (Vec3){[kv[1] floatValue], m.ovalPlaneRot.y, m.ovalPlaneRot.z};
                else if([kv[0] isEqualToString:@"ovalroty"])
                    m.ovalPlaneRot = (Vec3){m.ovalPlaneRot.x, [kv[1] floatValue], m.ovalPlaneRot.z};
                else if([kv[0] isEqualToString:@"ovalrotz"])
                    m.ovalPlaneRot = (Vec3){m.ovalPlaneRot.x, m.ovalPlaneRot.y, [kv[1] floatValue]};
                else if([kv[0] isEqualToString:@"ovalrev"])
                    m.ovalRev = [kv[1] intValue] != 0;
                else if([kv[0] isEqualToString:@"rotsync"])
                    m.rotSync = [kv[1] intValue] != 0;
                else if([kv[0] isEqualToString:@"rotrev"])
                    m.rotRev = [kv[1] intValue] != 0;
            }

            [s.models addObject:m];
        }
    }

    if(!s.textureRoot.length)
        s.textureRoot = sceneDir;

    return s;
}
@end

typedef struct {
    V3 p[3];
    float uv[3][2];
    int texIndex;
} POFTri;

typedef struct {
    GLuint   vao;
    GLuint   vbo;
    GLsizei  count;
    int      texIndex;
} VBOBatch;

@interface POFSub : NSObject
@property(nonatomic) int sid;
@property(nonatomic) int parent;
@property(nonatomic) V3 offset;
@property(nonatomic) V3 center;
@property(nonatomic, strong) NSMutableData *tris;   // POFTri[]
@property(nonatomic, strong) NSMutableData *glow;   // V3[]
@property(nonatomic) float uvMinU;
@property(nonatomic) float uvMaxU;
@property(nonatomic) float uvMinV;
@property(nonatomic) float uvMaxV;
@property(nonatomic) BOOL hasUVStats;
@property(nonatomic) BOOL rotates;
@property(nonatomic) int movementType;
@property(nonatomic) int movementAxis;
@property(nonatomic) float spin;
@property(nonatomic, strong) NSMutableData *vboBatches;
@property(nonatomic) BOOL vbosBuilt;
@property(nonatomic, copy) NSString *tex;
@property(nonatomic, copy) NSString *name;
@end

@implementation POFSub
- (instancetype)init
{
    if((self = [super init]))
    {
        _uvMinU =  999999.0f;
        _uvMinV =  999999.0f;
        _uvMaxU = -999999.0f;
        _uvMaxV = -999999.0f;
    }
    return self;
}
@end

@interface POFMesh : NSObject
@property(nonatomic, strong) NSMutableArray *subs;
@property(nonatomic, strong) NSMutableArray *textures;
@end

@implementation POFMesh
@end

static BOOL BoundsOK(NSUInteger off, NSUInteger need, NSUInteger end)
{
    return off <= end && need <= end - off;
}

static BOOL ReadBPOFString(const uint8_t *b, NSUInteger *io, NSUInteger end, NSString **out)
{
    if(!BoundsOK(*io, 4, end))
        return NO;

    uint32_t len = U32(b + *io);
    *io += 4;

    if(!BoundsOK(*io, len, end))
        return NO;

    *out = Str(b + *io, len);
    *io += len;
    return YES;
}

static void UpdateUVStats(POFSub *s, float u, float v)
{
    if(u < s.uvMinU) s.uvMinU = u;
    if(u > s.uvMaxU) s.uvMaxU = u;
    if(v < s.uvMinV) s.uvMinV = v;
    if(v > s.uvMaxV) s.uvMaxV = v;
    s.hasUVStats = YES;
}

static void AppendPOFTri(POFSub *sub,
                         NSMutableData *dst,
                         V3 a, float au, float av,
                         V3 b, float bu, float bv,
                         V3 c, float cu, float cv,
                         int texIndex)
{
    UpdateUVStats(sub, au, av);
    UpdateUVStats(sub, bu, bv);
    UpdateUVStats(sub, cu, cv);

    POFTri t;
    t.p[0] = a; t.uv[0][0] = au; t.uv[0][1] = av;
    t.p[1] = b; t.uv[1][0] = bu; t.uv[1][1] = bv;
    t.p[2] = c; t.uv[2][0] = cu; t.uv[2][1] = cv;
    t.texIndex = texIndex;
    [dst appendBytes:&t length:sizeof(t)];
}

static BOOL ParseDEFPOINTSAt(const uint8_t *b, NSUInteger pos, NSUInteger end, NSMutableArray *points)
{
    if(!BoundsOK(pos, 20, end))
        return NO;

    uint32_t op = U32(b + pos + 0);
    uint32_t len = U32(b + pos + 4);

    if(op != 1 || len < 20 || !BoundsOK(pos, len, end))
        return NO;

    NSUInteger d = pos + 8;
    NSUInteger opEnd = pos + len;

    uint32_t nverts = U32(b + d + 0);
    uint32_t nnorms = U32(b + d + 4);
    uint32_t dataOffset = U32(b + d + 8);

    (void)nnorms;

    if(nverts == 0 || nverts > 65535)
        return NO;

    NSUInteger counts = d + 12;
    NSUInteger q = pos + dataOffset;

    if(!BoundsOK(counts, nverts, opEnd) || !BoundsOK(q, 0, opEnd))
        return NO;

    [points removeAllObjects];

    for(uint32_t i = 0; i < nverts; i++)
    {
        if(!BoundsOK(q, 12, opEnd))
            return NO;

        V3 v = { F32(b + q), F32(b + q + 4), F32(b + q + 8) };
        q += 12;

        uint8_t normCount = b[counts + i];
        NSUInteger normBytes = (NSUInteger)normCount * 12;

        if(!BoundsOK(q, normBytes, opEnd))
            return NO;

        q += normBytes;
        [points addObject:[NSData dataWithBytes:&v length:sizeof(V3)]];
    }

    NSLog(@"[POF] DEFPOINTS pos=%lu verts=%u len=%u dataOffset=%u",
          (unsigned long)pos, nverts, len, dataOffset);

    return points.count > 0;
}

static BOOL ParseFlatPolyAt(const uint8_t *b, NSUInteger pos, NSUInteger end, NSArray *points, POFSub *s)
{
    if(!BoundsOK(pos, 44, end))
        return NO;

    uint32_t op = U32(b + pos + 0);
    uint32_t len = U32(b + pos + 4);

    if(op != 2 || len < 44 || !BoundsOK(pos, len, end))
        return NO;

    NSUInteger d = pos + 8;
    NSUInteger opEnd = pos + len;

    uint32_t nv = U32(b + d + 28);
    NSUInteger q = d + 36;

    if(nv < 3 || nv > 256)
        return NO;

    if(!BoundsOK(q, (NSUInteger)nv * 4, opEnd))
        return NO;

    V3 polyVerts[256];

    for(uint32_t i = 0; i < nv; i++)
    {
        uint16_t vi = U16(b + q);
        q += 4;

        if(vi >= points.count)
            return NO;

        NSData *pd = points[vi];
        memcpy(&polyVerts[i], pd.bytes, sizeof(V3));
    }

    for(uint32_t i = 1; i + 1 < nv; i++)
    {
        AppendPOFTri(s,
                     s.tris,
                     polyVerts[0], 0, 0,
                     polyVerts[i], 0, 0,
                     polyVerts[i + 1], 0, 0,
                     -1);
    }

    return YES;
}

static BOOL ParseTmapPolyAt(const uint8_t *b, NSUInteger pos, NSUInteger end, NSArray *points, POFSub *s)
{
    if(!BoundsOK(pos, 44, end))
        return NO;

    uint32_t op = U32(b + pos + 0);
    uint32_t len = U32(b + pos + 4);

    if(op != 3 || len < 44 || !BoundsOK(pos, len, end))
        return NO;

    NSUInteger d = pos + 8;
    NSUInteger opEnd = pos + len;

    uint32_t nv = U32(b + d + 28);
    int texIndex = (int)U32(b + d + 32);
    NSUInteger q = d + 36;

    if(nv < 3 || nv > 256)
        return NO;

    if(!BoundsOK(q, (NSUInteger)nv * 12, opEnd))
        return NO;

    V3 polyVerts[256];
    float uvs[256][2];

    for(uint32_t i = 0; i < nv; i++)
    {
        uint16_t vi = U16(b + q);
        float u = F32(b + q + 4);
        float v = F32(b + q + 8);
        q += 12;

        if(vi >= points.count)
            return NO;

        NSData *pd = points[vi];
        memcpy(&polyVerts[i], pd.bytes, sizeof(V3));
        uvs[i][0] = u;
        uvs[i][1] = v;
    }

    for(uint32_t i = 1; i + 1 < nv; i++)
    {
        AppendPOFTri(s,
                     s.tris,
                     polyVerts[0], uvs[0][0], uvs[0][1],
                     polyVerts[i], uvs[i][0], uvs[i][1],
                     polyVerts[i + 1], uvs[i + 1][0], uvs[i + 1][1],
                     texIndex);
    }

    return YES;
}

static void BSPCollectAt(const uint8_t *b,
                         NSUInteger pos,
                         NSUInteger start,
                         NSUInteger end,
                         NSMutableSet *visited,
                         NSMutableArray *points,
                         POFSub *s,
                         NSUInteger *defCount,
                         NSUInteger *flatCount,
                         NSUInteger *tmapCount,
                         NSUInteger depth)
{
    if(depth > 256 || !BoundsOK(pos, 8, end))
        return;

    NSNumber *key = @(pos);
    if([visited containsObject:key])
        return;
    [visited addObject:key];

    uint32_t op = U32(b + pos);
    uint32_t len = U32(b + pos + 4);

    if(op == 0)
        return;

    if(len < 8 || !BoundsOK(pos, len, end))
        return;

    if(op == 1)
    {
        NSMutableArray *candidate = [NSMutableArray array];
        if(ParseDEFPOINTSAt(b, pos, end, candidate))
        {
            [points removeAllObjects];
            [points addObjectsFromArray:candidate];
            (*defCount)++;
        }
    }
    else if(op == 2)
    {
        if(points.count > 0)
        {
            NSUInteger old = s.tris.length;
            if(ParseFlatPolyAt(b, pos, end, points, s) && s.tris.length > old)
                (*flatCount)++;
        }
    }
    else if(op == 3)
    {
        if(points.count > 0)
        {
            NSUInteger old = s.tris.length;
            if(ParseTmapPolyAt(b, pos, end, points, s) && s.tris.length > old)
                (*tmapCount)++;
        }
    }
    else if(op == 4)
    {
        // SORTNORM layout from PCS2 BSP_SortNorm::Read:
        // normal vec3, point vec3, reserved int,
        // front_offset, back_offset, prelist_offset, postlist_offset, online_offset,
        // bbox min vec3, bbox max vec3. Offsets are relative to this SORTNORM block.
        NSUInteger d = pos + 8;
        if(BoundsOK(d, 72 - 8, pos + len))
        {
            int32_t offsets[5];
            offsets[0] = (int32_t)U32(b + d + 28); // front
            offsets[1] = (int32_t)U32(b + d + 32); // back
            offsets[2] = (int32_t)U32(b + d + 36); // prelist
            offsets[3] = (int32_t)U32(b + d + 40); // postlist
            offsets[4] = (int32_t)U32(b + d + 44); // online

            for(int i = 0; i < 5; i++)
            {
                if(offsets[i] > 0)
                {
                    NSUInteger child = pos + (NSUInteger)offsets[i];
                    if(child >= start && child < end)
                        BSPCollectAt(b, child, start, end, visited, points, s,
                                     defCount, flatCount, tmapCount, depth + 1);
                }
            }
        }
    }

    // Also parse the physical next block. PCS2's BSP::DataIn consumes sequential blocks,
    // while SORTNORM offsets reference branches. Doing both catches packed and branch-heavy BSPs.
    NSUInteger next = pos + len;
    if(next > pos && next < end)
        BSPCollectAt(b, next, start, end, visited, points, s,
                     defCount, flatCount, tmapCount, depth + 1);
}

static BOOL ParsePOF2BSP(const uint8_t *b, NSUInteger start, NSUInteger size, POFSub *s)
{
    NSUInteger end = start + size;
    if(end < start)
        return NO;

    NSMutableArray *points = [NSMutableArray array];
    NSUInteger defCount = 0;
    NSUInteger flatCount = 0;
    NSUInteger tmapCount = 0;
    NSUInteger before = s.tris.length / sizeof(POFTri);

    // First try the real BSP graph from the beginning of the BSP data.
    NSMutableSet *visited = [NSMutableSet set];
    BSPCollectAt(b, start, start, end, visited, points, s,
                 &defCount, &flatCount, &tmapCount, 0);

    // Some malformed/variant files contain valid blocks not reachable from the first node.
    // Fallback: aligned linear pass by block size, not byte scanning.
    if((s.tris.length / sizeof(POFTri)) == before)
    {
        points = [NSMutableArray array];
        visited = [NSMutableSet set];
        NSUInteger pos = start;

        while(BoundsOK(pos, 8, end))
        {
            uint32_t op = U32(b + pos);
            uint32_t len = U32(b + pos + 4);
            if(op == 0)
                break;
            if(len < 8 || !BoundsOK(pos, len, end))
                break;

            BSPCollectAt(b, pos, start, end, visited, points, s,
                         &defCount, &flatCount, &tmapCount, 0);
            pos += len;
        }
    }

    // Last-resort scan: useful if a SORTNORM offset base differs in a variant file.
    if((s.tris.length / sizeof(POFTri)) == before)
    {
        points = [NSMutableArray array];

        for(NSUInteger pos = start; BoundsOK(pos, 8, end); pos += 4)
        {
            if(U32(b + pos) == 1)
            {
                NSMutableArray *candidate = [NSMutableArray array];
                if(ParseDEFPOINTSAt(b, pos, end, candidate))
                {
                    points = candidate;
                    defCount++;
                    break;
                }
            }
        }

        if(points.count > 0)
        {
            for(NSUInteger pos = start; BoundsOK(pos, 8, end); pos += 4)
            {
                uint32_t op = U32(b + pos);
                if(op == 2)
                {
                    NSUInteger old = s.tris.length;
                    if(ParseFlatPolyAt(b, pos, end, points, s) && s.tris.length > old)
                        flatCount++;
                }
                else if(op == 3)
                {
                    NSUInteger old = s.tris.length;
                    if(ParseTmapPolyAt(b, pos, end, points, s) && s.tris.length > old)
                        tmapCount++;
                }
            }
        }
    }

    NSUInteger after = s.tris.length / sizeof(POFTri);

    NSLog(@"[POF] BSP extract def=%lu flat=%lu tmap=%lu trisAdded=%lu totalTris=%lu firstId=%u firstSize=%u",
          (unsigned long)defCount,
          (unsigned long)flatCount,
          (unsigned long)tmapCount,
          (unsigned long)(after - before),
          (unsigned long)after,
          BoundsOK(start, 4, end) ? U32(b + start) : 0,
          BoundsOK(start + 4, 4, end) ? U32(b + start + 4) : 0);

    return after > before;
}

static POFMesh *LoadPOFDetail0(NSString *path, NSString **err)
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    if(!d || d.length < 12)
    {
        if(err) *err = @"unreadable";
        return nil;
    }

    const uint8_t *b = d.bytes;

    if(memcmp(b, "PSPO", 4) != 0)
    {
        if(err) *err = @"bad signature";
        return nil;
    }

    NSMutableArray *detail = [NSMutableArray array];
    NSMutableDictionary *objById = [NSMutableDictionary dictionary];
    NSMutableArray *textures = [NSMutableArray array];

    NSUInteger o = 8;

    while(o + 8 <= d.length)
    {
        const uint8_t *chunk = b + o;
        NSString *chunkId = FourCCString(chunk);
        uint32_t len = U32(chunk + 4);
        NSUInteger p = o + 8;

        if(p + len > d.length)
        {
            NSLog(@"[POF] top-level chunk %@ overruns file at offset %lu len %u",
                  chunkId, (unsigned long)o, len);
            break;
        }

        if([chunkId isEqualToString:@"TXTR"])
        {
            // PCS2 Parse_Memory_TXTR: uint32 count followed by count BPOF strings.
            NSUInteger q = p;
            if(BoundsOK(q, 4, p + len))
            {
                uint32_t numTextures = U32(b + q);
                q += 4;

                for(uint32_t i = 0; i < numTextures; i++)
                {
                    NSString *t = @"";
                    if(ReadBPOFString(b, &q, p + len, &t))
                    {
                        if(t.length)
                            [textures addObject:t];
                    }
                    else
                    {
                        NSLog(@"[POF] TXTR failed reading texture %u/%u", i, numTextures);
                        break;
                    }
                }
            }
        }
        else if([chunkId isEqualToString:@"HDR2"] && len >= 40)
        {
            uint32_t nd = U32(b + p + 36);
            NSUInteger q = p + 40;

            for(uint32_t i = 0; i < nd && q + 4 <= p + len; i++, q += 4)
                [detail addObject:@((int)U32(b + q))];
        }
        else if([chunkId isEqualToString:@"OBJ2"] && len >= 76)
        {
            NSUInteger end = p + len;
            NSUInteger q = p;

            POFSub *s = [POFSub new];
            s.tris = [NSMutableData data];
            s.glow = [NSMutableData data];
            s.spin = 20.0f;

            // PCS2 Parse_Memory_OBJ2 order:
            // int submodel_number, float radius, int parent,
            // vec3 offset, vec3 geometric_center, vec3 bbox_min, vec3 bbox_max,
            // BPOF string name, BPOF string properties,
            // int movement_type, int movement_axis, int reserved,
            // int bsp_data_size, byte bsp_data[bsp_data_size].
            s.sid = (int)U32(b + q); q += 4;
            float radius = F32(b + q); q += 4;
            s.parent = (int)U32(b + q); q += 4;

            s.offset = (V3){ F32(b + q), F32(b + q + 4), F32(b + q + 8) }; q += 12;
            s.center = (V3){ F32(b + q), F32(b + q + 4), F32(b + q + 8) }; q += 12;

            V3 bboxMin = { F32(b + q), F32(b + q + 4), F32(b + q + 8) }; q += 12;
            V3 bboxMax = { F32(b + q), F32(b + q + 4), F32(b + q + 8) }; q += 12;
            (void)bboxMin;
            (void)bboxMax;

            NSString *name = @"";
            NSString *props = @"";

            if(!ReadBPOFString(b, &q, end, &name))
            {
                NSLog(@"[POF] OBJ2 sid=%d failed reading name", s.sid);
                objById[@(s.sid)] = s;
                continue;
            }
            s.name = name;

            if(!ReadBPOFString(b, &q, end, &props))
            {
                NSLog(@"[POF] OBJ2 sid=%d failed reading properties", s.sid);
                objById[@(s.sid)] = s;
                continue;
            }

            if(!BoundsOK(q, 16, end))
            {
                NSLog(@"[POF] OBJ2 sid=%d truncated before movement/BSP header", s.sid);
                objById[@(s.sid)] = s;
                continue;
            }

            int movementType = (int)U32(b + q); q += 4;
            int movementAxis = (int)U32(b + q); q += 4;
            int reserved = (int)U32(b + q); q += 4;
            uint32_t bspSize = U32(b + q); q += 4;
            NSUInteger bspStart = q;

            (void)reserved;

            s.movementType = movementType;
            s.movementAxis = movementAxis;

            if(movementType >= 0)
            {
                s.rotates = YES;

                NSRange rotTag = [[props lowercaseString] rangeOfString:@"$rotate="];
                if(rotTag.location != NSNotFound)
                {
                    float rate = [[props substringFromIndex:rotTag.location + rotTag.length] floatValue];
                    if(rate != 0.0f)
                        s.spin = rate;
                }
            }

            if(!s.tex.length && textures.count)
                s.tex = textures[0];

            if(BoundsOK(bspStart, bspSize, end))
            {
                if(!ParsePOF2BSP(b, bspStart, bspSize, s))
                    NSLog(@"[POF] sid=%d BSP parse failed", s.sid);
            }
            else
            {
                NSLog(@"[POF] sid=%d invalid BSP bounds start=%lu size=%u objectEnd=%lu",
                      s.sid, (unsigned long)bspStart, bspSize, (unsigned long)end);
            }

            objById[@(s.sid)] = s;

            NSLog(@"[POF] OBJ2 sid=%d parent=%d name=%@ props=%@ radius=%.2f move=%d axis=%d offset=(%.2f %.2f %.2f) bsp=%u tris=%lu uv=(%.4f..%.4f, %.4f..%.4f)",
                  s.sid,
                  s.parent,
                  name,
                  props,
                  radius,
                  movementType,
                  movementAxis,
                  s.offset.x,
                  s.offset.y,
                  s.offset.z,
                  bspSize,
                  (unsigned long)(s.tris.length / sizeof(POFTri)),
                  s.hasUVStats ? s.uvMinU : 0.0f,
                  s.hasUVStats ? s.uvMaxU : 0.0f,
                  s.hasUVStats ? s.uvMinV : 0.0f,
                  s.hasUVStats ? s.uvMaxV : 0.0f);
        }

        o = p + len;
    }

    POFMesh *m = [POFMesh new];
    m.subs = [NSMutableArray array];
    m.textures = textures;

    if(detail.count > 0)
    {
        int lod0root = [detail[0] intValue];
        NSMutableSet *lod0ids = [NSMutableSet set];
        NSMutableArray *queue = [NSMutableArray arrayWithObject:@(lod0root)];

        while(queue.count > 0)
        {
            NSNumber *cur = queue[0];
            [queue removeObjectAtIndex:0];

            if([lod0ids containsObject:cur])
                continue;

            [lod0ids addObject:cur];

            for(NSNumber *k in objById)
            {
                POFSub *s = objById[k];
                if(s.parent == cur.intValue)
                    [queue addObject:@(s.sid)];
            }
        }

        for(NSNumber *k in objById)
        {
            POFSub *s = objById[k];
            if([lod0ids containsObject:@(s.sid)])
                [m.subs addObject:s];
        }

        if(m.subs.count > 0)
        {
            if(err) *err = [NSString stringWithFormat:@"lod0 subobjects=%lu", (unsigned long)m.subs.count];
            return m;
        }
    }

    int top = INT_MAX;

    for(NSNumber *k in objById)
    {
        POFSub *s = objById[k];
        if(s.parent < 0 && s.sid < top)
            top = s.sid;
    }

    for(NSNumber *k in objById)
    {
        POFSub *s = objById[k];
        if(s.parent < 0 || s.parent == top)
            [m.subs addObject:s];
    }

    if(m.subs.count == 0)
    {
        if(err) *err = @"no drawable subobjects";
        return nil;
    }

    if(err) *err = [NSString stringWithFormat:@"lod info missing, fallback subobjects=%lu", (unsigned long)m.subs.count];
    return m;
}

// Set filtering params on the currently-bound GL_TEXTURE_2D.
// Generates mipmaps and enables trilinear + anisotropic filtering when available.
static void ApplyTexParams(void)
{
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

    if(glGenerateMipmap)
    {
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);

        if(GLEW_EXT_texture_filter_anisotropic)
        {
            GLfloat maxAniso = 1.0f;
            glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &maxAniso);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT,
                            fminf(maxAniso, 8.0f));
        }
    }
    else
    {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    }
}

static GLuint CheckerTexture(void)
{
    unsigned char p[16] = {
        255,255,255,255, 20,20,20,255,
        20,20,20,255, 255,255,255,255
    };

    GLuint t = 0;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, p);
    ApplyTexParams();
    return t;
}

static BOOL LoadPCXRGBA(NSString *p, NSMutableData **rgbaOut, NSInteger *wOut, NSInteger *hOut)
{
    NSData *data = [NSData dataWithContentsOfFile:p];
    if(!data || data.length < 769)
        return NO;

    const uint8_t *src = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;

    if(src[0] != 0x0A)
        return NO;

    uint8_t encoding = src[2];
    uint8_t bitsPerPixel = src[3];
    uint16_t xmin = U16(src + 4);
    uint16_t ymin = U16(src + 6);
    uint16_t xmax = U16(src + 8);
    uint16_t ymax = U16(src + 10);
    uint8_t planes = src[65];
    uint16_t bytesPerLine = U16(src + 66);

    if(encoding != 1 || bitsPerPixel != 8 || planes != 1)
    {
        NSLog(@"[TEX] unsupported PCX format %@ bpp=%u planes=%u encoding=%u", p, bitsPerPixel, planes, encoding);
        return NO;
    }

    NSInteger w = (NSInteger)xmax - (NSInteger)xmin + 1;
    NSInteger h = (NSInteger)ymax - (NSInteger)ymin + 1;

    if(w <= 0 || h <= 0 || bytesPerLine < w)
        return NO;

    if(len < 769 || src[len - 769] != 0x0C)
    {
        NSLog(@"[TEX] PCX missing 256-colour palette %@", p);
        return NO;
    }

    const uint8_t *pal = src + len - 768;
    NSUInteger imageEnd = len - 769;
    NSUInteger ip = 128;

    NSMutableData *indices = [NSMutableData dataWithLength:(NSUInteger)bytesPerLine * (NSUInteger)h];
    uint8_t *idx = (uint8_t *)indices.mutableBytes;

    for(NSInteger y = 0; y < h; y++)
    {
        NSInteger x = 0;
        while(x < bytesPerLine && ip < imageEnd)
        {
            uint8_t c = src[ip++];
            uint8_t count = 1;
            uint8_t val = c;

            if((c & 0xC0) == 0xC0)
            {
                count = c & 0x3F;
                if(ip >= imageEnd)
                    break;
                val = src[ip++];
            }

            for(uint8_t r = 0; r < count && x < bytesPerLine; r++, x++)
                idx[(NSUInteger)y * (NSUInteger)bytesPerLine + (NSUInteger)x] = val;
        }
    }

    NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)w * (NSUInteger)h * 4];
    uint8_t *out = (uint8_t *)rgba.mutableBytes;

    for(NSInteger y = 0; y < h; y++)
    {
        for(NSInteger x = 0; x < w; x++)
        {
            uint8_t pi = idx[(NSUInteger)y * (NSUInteger)bytesPerLine + (NSUInteger)x];
            NSUInteger off = ((NSUInteger)y * (NSUInteger)w + (NSUInteger)x) * 4;
            out[off + 0] = pal[(NSUInteger)pi * 3 + 0];
            out[off + 1] = pal[(NSUInteger)pi * 3 + 1];
            out[off + 2] = pal[(NSUInteger)pi * 3 + 2];
            out[off + 3] = 255;
        }
    }

    *rgbaOut = rgba;
    *wOut = w;
    *hOut = h;
    return YES;
}

static void DecodeRGB565(uint16_t c, uint8_t rgba[4])
{
    uint8_t r = (uint8_t)((c >> 11) & 31);
    uint8_t g = (uint8_t)((c >> 5) & 63);
    uint8_t b = (uint8_t)(c & 31);

    rgba[0] = (uint8_t)((r << 3) | (r >> 2));
    rgba[1] = (uint8_t)((g << 2) | (g >> 4));
    rgba[2] = (uint8_t)((b << 3) | (b >> 2));
    rgba[3] = 255;
}

static void StorePixel(uint8_t *out, uint32_t w, uint32_t h, uint32_t x, uint32_t y, const uint8_t rgba[4])
{
    if(x >= w || y >= h)
        return;

    NSUInteger off = ((NSUInteger)y * (NSUInteger)w + (NSUInteger)x) * 4;
    out[off + 0] = rgba[0];
    out[off + 1] = rgba[1];
    out[off + 2] = rgba[2];
    out[off + 3] = rgba[3];
}

static BOOL DecodeDXT1ToRGBA(const uint8_t *src, NSUInteger srcLen, uint32_t w, uint32_t h, NSMutableData **rgbaOut)
{
    uint32_t blocksX = (w + 3) / 4;
    uint32_t blocksY = (h + 3) / 4;
    NSUInteger need = (NSUInteger)blocksX * (NSUInteger)blocksY * 8;

    if(srcLen < need)
        return NO;

    NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)w * (NSUInteger)h * 4];
    uint8_t *out = (uint8_t *)rgba.mutableBytes;
    NSUInteger p = 0;

    for(uint32_t by = 0; by < blocksY; by++)
    {
        for(uint32_t bx = 0; bx < blocksX; bx++)
        {
            uint16_t c0 = U16(src + p + 0);
            uint16_t c1 = U16(src + p + 2);
            uint32_t bits = U32(src + p + 4);
            p += 8;

            uint8_t col[4][4];
            DecodeRGB565(c0, col[0]);
            DecodeRGB565(c1, col[1]);

            if(c0 > c1)
            {
                for(int i = 0; i < 3; i++)
                {
                    col[2][i] = (uint8_t)((2 * col[0][i] + col[1][i]) / 3);
                    col[3][i] = (uint8_t)((col[0][i] + 2 * col[1][i]) / 3);
                }
                col[2][3] = 255;
                col[3][3] = 255;
            }
            else
            {
                for(int i = 0; i < 3; i++)
                {
                    col[2][i] = (uint8_t)((col[0][i] + col[1][i]) / 2);
                    col[3][i] = 0;
                }
                col[2][3] = 255;
                col[3][3] = 0;
            }

            for(uint32_t py = 0; py < 4; py++)
            {
                for(uint32_t px = 0; px < 4; px++)
                {
                    uint32_t idx = bits & 0x3;
                    bits >>= 2;
                    StorePixel(out, w, h, bx * 4 + px, by * 4 + py, col[idx]);
                }
            }
        }
    }

    *rgbaOut = rgba;
    return YES;
}

static BOOL DecodeDXT5ToRGBA(const uint8_t *src, NSUInteger srcLen, uint32_t w, uint32_t h, NSMutableData **rgbaOut)
{
    uint32_t blocksX = (w + 3) / 4;
    uint32_t blocksY = (h + 3) / 4;
    NSUInteger need = (NSUInteger)blocksX * (NSUInteger)blocksY * 16;

    if(srcLen < need)
        return NO;

    NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)w * (NSUInteger)h * 4];
    uint8_t *out = (uint8_t *)rgba.mutableBytes;
    NSUInteger p = 0;

    for(uint32_t by = 0; by < blocksY; by++)
    {
        for(uint32_t bx = 0; bx < blocksX; bx++)
        {
            uint8_t a0 = src[p + 0];
            uint8_t a1 = src[p + 1];
            uint64_t alphaBits = 0;
            for(int i = 0; i < 6; i++)
                alphaBits |= ((uint64_t)src[p + 2 + i]) << (8 * i);

            uint8_t alpha[8];
            alpha[0] = a0;
            alpha[1] = a1;

            if(a0 > a1)
            {
                alpha[2] = (uint8_t)((6 * a0 + 1 * a1) / 7);
                alpha[3] = (uint8_t)((5 * a0 + 2 * a1) / 7);
                alpha[4] = (uint8_t)((4 * a0 + 3 * a1) / 7);
                alpha[5] = (uint8_t)((3 * a0 + 4 * a1) / 7);
                alpha[6] = (uint8_t)((2 * a0 + 5 * a1) / 7);
                alpha[7] = (uint8_t)((1 * a0 + 6 * a1) / 7);
            }
            else
            {
                alpha[2] = (uint8_t)((4 * a0 + 1 * a1) / 5);
                alpha[3] = (uint8_t)((3 * a0 + 2 * a1) / 5);
                alpha[4] = (uint8_t)((2 * a0 + 3 * a1) / 5);
                alpha[5] = (uint8_t)((1 * a0 + 4 * a1) / 5);
                alpha[6] = 0;
                alpha[7] = 255;
            }

            uint16_t c0 = U16(src + p + 8);
            uint16_t c1 = U16(src + p + 10);
            uint32_t bits = U32(src + p + 12);
            p += 16;

            uint8_t col[4][4];
            DecodeRGB565(c0, col[0]);
            DecodeRGB565(c1, col[1]);

            for(int i = 0; i < 3; i++)
            {
                col[2][i] = (uint8_t)((2 * col[0][i] + col[1][i]) / 3);
                col[3][i] = (uint8_t)((col[0][i] + 2 * col[1][i]) / 3);
            }
            col[2][3] = 255;
            col[3][3] = 255;

            for(uint32_t py = 0; py < 4; py++)
            {
                for(uint32_t px = 0; px < 4; px++)
                {
                    uint32_t colorIdx = bits & 0x3;
                    bits >>= 2;

                    uint32_t alphaIdx = (uint32_t)(alphaBits & 0x7);
                    alphaBits >>= 3;

                    uint8_t rgbaPix[4] = {
                        col[colorIdx][0],
                        col[colorIdx][1],
                        col[colorIdx][2],
                        alpha[alphaIdx]
                    };

                    StorePixel(out, w, h, bx * 4 + px, by * 4 + py, rgbaPix);
                }
            }
        }
    }

    *rgbaOut = rgba;
    return YES;
}

static GLuint UploadPlainRGBA(NSString *label, NSData *rgba, uint32_t w, uint32_t h)
{
    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA,
                 (GLsizei)w,
                 (GLsizei)h,
                 0,
                 GL_RGBA,
                 GL_UNSIGNED_BYTE,
                 rgba.bytes);

    GLenum err = glGetError();
    if(err != GL_NO_ERROR)
    {
        NSLog(@"[TEX] GL_RGBA upload failed %@ err=0x%x", label, err);
        glDeleteTextures(1, &tex);
        return CheckerTexture();
    }

    ApplyTexParams();
    return tex;
}

static BOOL UploadDDSDXT(NSString *p, GLuint *texOut)
{
    NSData *data = [NSData dataWithContentsOfFile:p];
    if(!data || data.length < 128)
        return NO;

    const uint8_t *b = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;

    if(memcmp(b, "DDS ", 4) != 0)
        return NO;

    uint32_t headerSize = U32(b + 4);
    if(headerSize != 124)
    {
        NSLog(@"[TEX] DDS bad header size %@ size=%u", p, headerSize);
        return NO;
    }

    uint32_t height = U32(b + 12);
    uint32_t width = U32(b + 16);
    uint32_t fourCC = U32(b + 84);

    if(width == 0 || height == 0)
        return NO;

    const uint8_t *image = b + 128;
    NSUInteger imageLen = len - 128;
    NSMutableData *rgba = nil;
    const char *fmt = NULL;
    BOOL ok = NO;

    if(fourCC == U32((const uint8_t *)"DXT1"))
    {
        fmt = "DXT1";
        ok = DecodeDXT1ToRGBA(image, imageLen, width, height, &rgba);
    }
    else if(fourCC == U32((const uint8_t *)"DXT5"))
    {
        fmt = "DXT5";
        ok = DecodeDXT5ToRGBA(image, imageLen, width, height, &rgba);
    }
    else
    {
        char fcc[5] = {0};
        memcpy(fcc, b + 84, 4);
        NSLog(@"[TEX] unsupported DDS fourCC %@ '%s'", p, fcc);
        return NO;
    }

    if(!ok || !rgba)
    {
        NSLog(@"[TEX] DDS software decode failed %@ format=%s", p, fmt ?: "?");
        return NO;
    }

    GLuint tex = UploadPlainRGBA(p, rgba, width, height);
    NSLog(@"[TEX] uploaded DDS software-decoded %@ %ux%u format=%s id=%u", p, width, height, fmt, tex);

    *texOut = tex;
    return YES;
}

static NSString *CaseInsensitiveExistingPath(NSString *candidate)
{
    if(candidate.length == 0)
        return nil;

    NSFileManager *fm = [NSFileManager defaultManager];

    if([fm fileExistsAtPath:candidate])
        return candidate;

    NSString *dir = [candidate stringByDeletingLastPathComponent];
    NSString *leaf = [candidate lastPathComponent];
    NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];

    for(NSString *item in items)
    {
        if([item caseInsensitiveCompare:leaf] == NSOrderedSame)
            return [dir stringByAppendingPathComponent:item];
    }

    return nil;
}

static GLuint LoadTexture(NSString *p)
{
    if(!p.length || ![[NSFileManager defaultManager] fileExistsAtPath:p])
    {
        NSLog(@"[TEX] missing file %@, using checker", p ?: @"<nil>");
        return CheckerTexture();
    }

    GLuint ddsTex = 0;
    if([[[p pathExtension] lowercaseString] isEqualToString:@"dds"] &&
       UploadDDSDXT(p, &ddsTex))
    {
        return ddsTex;
    }

    NSMutableData *pcxRGBA = nil;
    NSInteger pcxW = 0;
    NSInteger pcxH = 0;

    if([[[p pathExtension] lowercaseString] isEqualToString:@"pcx"] &&
       LoadPCXRGBA(p, &pcxRGBA, &pcxW, &pcxH))
    {
        GLuint t = 0;
        glGenTextures(1, &t);
        glBindTexture(GL_TEXTURE_2D, t);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGBA,
                     (GLsizei)pcxW,
                     (GLsizei)pcxH,
                     0,
                     GL_RGBA,
                     GL_UNSIGNED_BYTE,
                     [pcxRGBA bytes]);

        ApplyTexParams();

        NSLog(@"[TEX] uploaded PCX %@ %ldx%ld id=%u", p, (long)pcxW, (long)pcxH, t);
        return t;
    }

    NSImage *img = [[NSImage alloc] initWithContentsOfFile:p];
    if(!img)
    {
        NSLog(@"[TEX] NSImage failed %@, using checker", p);
        return CheckerTexture();
    }

    NSBitmapImageRep *rep = nil;

    for(NSImageRep *r in [img representations])
    {
        if([r isKindOfClass:[NSBitmapImageRep class]])
        {
            rep = (NSBitmapImageRep *)r;
            break;
        }
    }

    if(!rep)
    {
        NSData *tiff = [img TIFFRepresentation];
        if(tiff)
        {
            NSArray *reps = [NSBitmapImageRep imageRepsWithData:tiff];
            for(NSImageRep *r in reps)
            {
                if([r isKindOfClass:[NSBitmapImageRep class]])
                {
                    rep = (NSBitmapImageRep *)r;
                    break;
                }
            }
        }
    }

    if(!rep)
    {
        NSLog(@"[TEX] no bitmap representation %@, using checker", p);
        return CheckerTexture();
    }

    NSInteger w = [rep pixelsWide];
    NSInteger h = [rep pixelsHigh];

    if(w <= 0 || h <= 0)
        return CheckerTexture();

    NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)w * (NSUInteger)h * 4];
    unsigned char *out = (unsigned char *)[rgba mutableBytes];

    for(NSInteger y = 0; y < h; y++)
    {
        for(NSInteger x = 0; x < w; x++)
        {
            NSColor *c = [rep colorAtX:x y:y];
            if(!c)
                c = [NSColor magentaColor];

            c = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if(!c)
                c = [NSColor magentaColor];

            NSUInteger off = ((NSUInteger)y * (NSUInteger)w + (NSUInteger)x) * 4;
            out[off + 0] = (unsigned char)(fmaxf(0.0f, fminf(1.0f, [c redComponent])) * 255.0f);
            out[off + 1] = (unsigned char)(fmaxf(0.0f, fminf(1.0f, [c greenComponent])) * 255.0f);
            out[off + 2] = (unsigned char)(fmaxf(0.0f, fminf(1.0f, [c blueComponent])) * 255.0f);
            out[off + 3] = (unsigned char)(fmaxf(0.0f, fminf(1.0f, [c alphaComponent])) * 255.0f);
        }
    }

    GLuint t = 0;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA,
                 (GLsizei)w,
                 (GLsizei)h,
                 0,
                 GL_RGBA,
                 GL_UNSIGNED_BYTE,
                 [rgba bytes]);

    ApplyTexParams();

    NSLog(@"[TEX] uploaded NSImage %@ %ldx%ld id=%u", p, (long)w, (long)h, t);
    return t;
}


@interface TextureMaterial : NSObject
@property(nonatomic) GLuint diffuse;
@property(nonatomic) GLuint glow;
@property(nonatomic) GLuint normal;
@property(nonatomic) GLuint shine;
@property(nonatomic, copy) NSString *baseName;
@property(nonatomic, copy) NSString *diffusePath;
@property(nonatomic, copy) NSString *glowPath;
@property(nonatomic, copy) NSString *normalPath;
@property(nonatomic, copy) NSString *shinePath;
@end

@implementation TextureMaterial
@end

// ---------------------------------------------------------------------------
// GL 3.3 Core shaders
// ---------------------------------------------------------------------------

// Mesh shader: lit rendering with per-vertex face normals, normal map, specular map
static const char *kMeshVertSrc =
    "#version 330 core\n"
    "layout(location = 0) in vec3 aPos;\n"
    "layout(location = 1) in vec3 aNormal;\n"
    "layout(location = 2) in vec2 aUV;\n"
    "uniform mat4 uModel;\n"
    "uniform mat4 uView;\n"
    "uniform mat4 uProj;\n"
    "out vec3 vViewPos;\n"
    "out vec3 vViewNormal;\n"
    "out vec2 vUV;\n"
    "void main() {\n"
    "    vec4 vp    = uView * uModel * vec4(aPos, 1.0);\n"
    "    vViewPos   = vp.xyz;\n"
    "    vViewNormal = mat3(uView * uModel) * aNormal;\n"
    "    vUV        = aUV;\n"
    "    gl_Position = uProj * vp;\n"
    "}\n";

static const char *kMeshFragSrc =
    "#version 330 core\n"
    "uniform sampler2D uDiffuse;\n"
    "uniform sampler2D uNormal;\n"
    "uniform sampler2D uShine;\n"
    "uniform vec3 uLightDir;\n"
    "uniform int  uHasNormal;\n"
    "uniform int  uHasShine;\n"
    "uniform int  uEmissive;\n"
    "in vec3 vViewPos;\n"
    "in vec3 vViewNormal;\n"
    "in vec2 vUV;\n"
    "out vec4 fragColor;\n"
    "void main() {\n"
    "    vec4 base = texture(uDiffuse, vUV);\n"
    // Emissive / glow pass: no lighting, output texture directly
    "    if(uEmissive != 0) { fragColor = base; return; }\n"
    // Base normal from interpolated vertex normal (face normal = flat shading)
    "    vec3 N = normalize(vViewNormal);\n"
    "    if(dot(N, -vViewPos) < 0.0) N = -N;\n"
    // Tangent-space normal map (uses position/UV screen derivatives, stable now that N is vertex-driven)
    "    if(uHasNormal != 0) {\n"
    "        vec3 dPdx = dFdx(vViewPos); vec3 dPdy = dFdy(vViewPos);\n"
    "        vec2 dUVdx = dFdx(vUV);    vec2 dUVdy = dFdy(vUV);\n"
    "        float det = dUVdx.x * dUVdy.y - dUVdy.x * dUVdx.y;\n"
    "        if(abs(det) > 1e-6) {\n"
    "            vec3 T  = normalize(( dUVdy.y * dPdx - dUVdx.y * dPdy) / det);\n"
    "            vec3 B  = normalize((-dUVdy.x * dPdx + dUVdx.x * dPdy) / det);\n"
    // DXT5nm (AG): alpha=X, green=Y, Z derived; RGB channels are filler
    "            vec4 ntex = texture(uNormal, vUV);\n"
    "            vec3 ns; ns.x = ntex.a*2.0-1.0; ns.y = ntex.g*2.0-1.0;\n"
    "            ns.z = sqrt(max(0.0, 1.0 - ns.x*ns.x - ns.y*ns.y));\n"
    "            N = normalize(mat3(T, B, N) * ns);\n"
    "        }\n"
    "    }\n"
    "    float NdotL = max(dot(N, uLightDir), 0.0);\n"
    "    vec3  V     = normalize(-vViewPos);\n"
    "    vec3  H     = normalize(uLightDir + V);\n"
    "    float spec  = pow(max(dot(N, H), 0.0), 32.0);\n"
    "    if(uHasShine != 0)\n"
    "        spec *= texture(uShine, vUV).r;\n"
    "    else\n"
    "        spec = 0.0;\n"
    "    vec3 lit = base.rgb * (0.2 + NdotL) + vec3(spec);\n"
    "    fragColor = vec4(lit, base.a);\n"
    "}\n";

// Flat shader: unlit geometry with per-vertex colour (stars, axes, orbit loops, placeholders)
static const char *kFlatVertSrc =
    "#version 330 core\n"
    "layout(location = 0) in vec3 aPos;\n"
    "layout(location = 1) in vec4 aColor;\n"
    "uniform mat4 uMVP;\n"
    "uniform float uPointSize;\n"
    "out vec4 vColor;\n"
    "void main() {\n"
    "    vColor = aColor;\n"
    "    gl_Position = uMVP * vec4(aPos, 1.0);\n"
    "    gl_PointSize = uPointSize;\n"
    "}\n";

static const char *kFlatFragSrc =
    "#version 330 core\n"
    "in vec4 vColor;\n"
    "uniform vec4 uColorMul;\n"
    "out vec4 fragColor;\n"
    "void main() {\n"
    "    fragColor = vColor * uColorMul;\n"
    "}\n";

static GLuint CompileShader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if(!ok)
    {
        char log[2048] = {0};
        glGetShaderInfoLog(s, sizeof(log) - 1, NULL, log);
        NSLog(@"[GLSL] compile error:\n%s", log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

static GLuint BuildProgram(const char *vertSrc, const char *fragSrc)
{
    GLuint vs = CompileShader(GL_VERTEX_SHADER,   vertSrc);
    GLuint fs = CompileShader(GL_FRAGMENT_SHADER, fragSrc);
    if(!vs || !fs) { if(vs) glDeleteShader(vs); if(fs) glDeleteShader(fs); return 0; }

    GLuint p = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, fs);
    glLinkProgram(p);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if(!ok)
    {
        char log[2048] = {0};
        glGetProgramInfoLog(p, sizeof(log) - 1, NULL, log);
        NSLog(@"[GLSL] link error:\n%s", log);
        glDeleteProgram(p);
        return 0;
    }
    return p;
}

// Build a flat-shader VAO from interleaved [x,y,z,r,g,b,a] float vertices
static void BuildFlatVAO(const float *verts, GLsizeiptr size, GLuint *vao, GLuint *vbo)
{
    glGenVertexArrays(1, vao);
    glGenBuffers(1, vbo);
    glBindVertexArray(*vao);
    glBindBuffer(GL_ARRAY_BUFFER, *vbo);
    glBufferData(GL_ARRAY_BUFFER, size, verts, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 7*sizeof(float), (void *)0);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 7*sizeof(float), (void *)(3*sizeof(float)));
    glEnableVertexAttribArray(1);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
}

@interface SpaceGLView : NSOpenGLView
- (instancetype)initWithFrame:(NSRect)f scene:(SceneDefinition *)s;
- (void)drawSubobject:(POFSub *)s mesh:(POFMesh *)pm children:(NSDictionary *)children elapsed:(float)elapsed reversedSubs:(NSSet *)reversedSubs modelMat:(Mat4)modelMat;
@end

@implementation SpaceGLView
{
    BOOL _drawing;
    SceneDefinition *_s;
    NSTimer *_t;
    NSTimeInterval _last;
    float _e;
    NSMutableDictionary *_mesh;
    NSMutableDictionary *_tex;
    NSMutableDictionary *_mat;
    NSMutableData *_stars;
    GLuint _skyboxTex;
    BOOL _skyboxLoaded;
    BOOL _glReady;
    // Mesh shader
    GLuint _shader;
    GLint _uModel, _uView, _uProj;
    GLint _uDiffuse, _uNormal, _uShine;
    GLint _uHasNormal, _uHasShine;
    GLint _uLightDir;
    GLint _uEmissive;
    // Flat shader
    GLuint _flatShader;
    GLint _uMVP, _uPointSize, _uColorMul;
    // CPU matrices
    Mat4 _proj;
    Mat4 _view;
    // Static geometry VAOs
    GLuint _starsVAO, _starsVBO;
    GLuint _axesVAO, _axesVBO;
    GLuint _cubeVAO, _cubeVBO;
    NSMutableArray *_loopVAOs;   // GLuint per _s.models entry (0 = no loop)
    NSMutableArray *_loopVBOs;
}

- (instancetype)initWithFrame:(NSRect)f scene:(SceneDefinition *)s
{
    NSOpenGLPixelFormatAttribute a[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFADepthSize, 24,
        0
    };

    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:a];

    if((self = [super initWithFrame:f pixelFormat:pf]))
    {
        _s = s;
        _last = [NSDate timeIntervalSinceReferenceDate];
        _mesh = [NSMutableDictionary dictionary];
        _tex = [NSMutableDictionary dictionary];
        _mat = [NSMutableDictionary dictionary];
        _stars = [NSMutableData dataWithLength:sizeof(V3) * 1500];

        V3 *q = (V3 *)_stars.mutableBytes;
        for(int i = 0; i < 1500; i++)
        {
            q[i] = (V3){
                ((float)arc4random() / (float)UINT32_MAX - 0.5f) * 40000.0f,
                ((float)arc4random() / (float)UINT32_MAX - 0.5f) * 40000.0f,
                -((float)arc4random() / (float)UINT32_MAX) * 40000.0f
            };
        }

        _t = [NSTimer timerWithTimeInterval:1.0 / 60.0
                                      target:self
                                    selector:@selector(onTick:)
                                    userInfo:nil
                                     repeats:YES];

        [[NSRunLoop currentRunLoop] addTimer:_t forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer:_t forMode:NSModalPanelRunLoopMode];
    }

    return self;
}

- (void)onTick:(id)x
{
    (void)x;

    // GNUstep/AppKit can coalesce or delay setNeedsDisplay: heavily.
    // Drive the animation explicitly so rotations/orbits do not appear to stall.
    [self display];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)e
{
    if([[e charactersIgnoringModifiers] length] && [[e charactersIgnoringModifiers] characterAtIndex:0] == 27)
    {
        [NSApp terminate:nil];
        return;
    }

    [super keyDown:e];
}

- (void)_initGL
{
    if(_glReady) return;
    _glReady = YES;

    glewExperimental = GL_TRUE;
    GLenum glewErr = glewInit();
    NSLog(@"[GLEW] init=%u GL3=%d version=%s", glewErr, (int)GLEW_VERSION_3_3,
          (const char *)glGetString(GL_VERSION));

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    glClearDepth(1.0);
    glEnable(GL_PROGRAM_POINT_SIZE);

    // Build mesh shader
    _shader = BuildProgram(kMeshVertSrc, kMeshFragSrc);
    NSLog(@"[GLSL] mesh program id=%u", _shader);
    if(_shader)
    {
        _uModel     = glGetUniformLocation(_shader, "uModel");
        _uView      = glGetUniformLocation(_shader, "uView");
        _uProj      = glGetUniformLocation(_shader, "uProj");
        _uDiffuse   = glGetUniformLocation(_shader, "uDiffuse");
        _uNormal    = glGetUniformLocation(_shader, "uNormal");
        _uShine     = glGetUniformLocation(_shader, "uShine");
        _uHasNormal = glGetUniformLocation(_shader, "uHasNormal");
        _uHasShine  = glGetUniformLocation(_shader, "uHasShine");
        _uLightDir  = glGetUniformLocation(_shader, "uLightDir");
        _uEmissive  = glGetUniformLocation(_shader, "uEmissive");

        glUseProgram(_shader);
        glUniform1i(_uDiffuse,  0);
        glUniform1i(_uNormal,   1);
        glUniform1i(_uShine,    2);
        glUniform1i(_uEmissive, 0);
        glUseProgram(0);
    }

    // Build flat shader
    _flatShader = BuildProgram(kFlatVertSrc, kFlatFragSrc);
    NSLog(@"[GLSL] flat program id=%u", _flatShader);
    if(_flatShader)
    {
        _uMVP       = glGetUniformLocation(_flatShader, "uMVP");
        _uPointSize = glGetUniformLocation(_flatShader, "uPointSize");
        _uColorMul  = glGetUniformLocation(_flatShader, "uColorMul");
    }

    // Stars VAO — 1500 white point vertices
    {
        V3 *st = (V3 *)_stars.bytes;
        float sv[1500 * 7];
        for(int i = 0; i < 1500; i++)
        {
            sv[i*7+0] = st[i].x; sv[i*7+1] = st[i].y; sv[i*7+2] = st[i].z;
            sv[i*7+3] = sv[i*7+4] = sv[i*7+5] = sv[i*7+6] = 1.0f;
        }
        BuildFlatVAO(sv, sizeof(sv), &_starsVAO, &_starsVBO);
    }

    // Axes VAO — 3 coloured line segments, fixed length 25
    {
        float ax[] = {
            0,0,0, 1,0,0,1,   25,0,0,  1,0,0,1,
            0,0,0, 0,1,0,1,   0,25,0,  0,1,0,1,
            0,0,0, 0,0,1,1,   0,0,25,  0,0,1,1
        };
        BuildFlatVAO(ax, sizeof(ax), &_axesVAO, &_axesVBO);
    }

    // Placeholder cube VAO — unit cube, white vertices, 36 tris
    {
        static const float pos[36*3] = {
            -1,-1,-1, -1,1,-1,  1,1,-1,  -1,-1,-1,  1,1,-1,  1,-1,-1,
            -1,-1, 1,  1,-1,1,  1,1, 1,  -1,-1, 1,  1,1, 1, -1, 1, 1,
            -1,-1,-1, -1,-1,1, -1,1, 1,  -1,-1,-1, -1,1, 1, -1, 1,-1,
             1,-1,-1,  1,1, 1,  1,-1,1,   1,-1,-1,  1,1,-1,  1, 1, 1,
            -1,-1,-1,  1,-1,1,  1,-1,-1, -1,-1,-1, -1,-1,1,  1,-1,1,
            -1, 1,-1, -1,1, 1,  1,1, 1,  -1, 1,-1,  1,1, 1,  1, 1,-1
        };
        float cv[36*7];
        for(int i = 0; i < 36; i++)
        {
            cv[i*7+0]=pos[i*3]; cv[i*7+1]=pos[i*3+1]; cv[i*7+2]=pos[i*3+2];
            cv[i*7+3]=cv[i*7+4]=cv[i*7+5]=cv[i*7+6]=1.0f;
        }
        BuildFlatVAO(cv, sizeof(cv), &_cubeVAO, &_cubeVBO);
    }

    // Orbit loop VAOs — one per scene model that has a path
    _loopVAOs = [[NSMutableArray alloc] init];
    _loopVBOs = [[NSMutableArray alloc] init];
    for(SceneModel *m in _s.models)
    {
        if(!m.hasOvalPath || m.ovalRadius <= 0)
        {
            [_loopVAOs addObject:@(0u)];
            [_loopVBOs addObject:@(0u)];
            continue;
        }
        float lv[64 * 7];
        for(int i = 0; i < 64; i++)
        {
            float a = DegToRad(360.0f * (float)i / 64.0f);
            Vec3 pt = V3RotXYZ((Vec3){cosf(a)*m.ovalRadius, 0.0f, sinf(a)*m.ovalRadius},
                               m.ovalPlaneRot);
            lv[i*7+0] = m.position.x + pt.x;
            lv[i*7+1] = m.position.y + pt.y;
            lv[i*7+2] = m.position.z + pt.z;
            lv[i*7+3] = 1.0f; lv[i*7+4] = 0.2f; lv[i*7+5] = 0.2f; lv[i*7+6] = 1.0f;
        }
        GLuint lVAO = 0, lVBO = 0;
        BuildFlatVAO(lv, sizeof(lv), &lVAO, &lVBO);
        [_loopVAOs addObject:@(lVAO)];
        [_loopVBOs addObject:@(lVBO)];
    }

    [self reshape];
}

- (void)prepareOpenGL
{
    [super prepareOpenGL];
    // Do NOT call _initGL here — on GNUstep, prepareOpenGL fires before the
    // context is made current, so glewInit() would bind nothing.  _initGL is
    // called lazily from drawRect: after makeCurrentContext succeeds.
}

- (void)reshape
{
    [super reshape];

    NSRect b = self.bounds;
    if(b.size.height <= 0)
        return;

    glViewport(0, 0, (GLsizei)b.size.width, (GLsizei)b.size.height);

    float asp = (float)b.size.width / (float)b.size.height;
    float n = VIEW_NEAR_PLANE;
    float f = VIEW_FAR_PLANE;
    float top = tanf(DegToRad(VIEW_FOV_Y_DEG * 0.5f)) * n;
    float right = top * asp;

    _proj = Mat4Frustum(-right, right, -top, top, n, f);
}

- (NSString *)textureFileForName:(NSString *)tn
{
    NSString *key = [tn ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!key.length)
        return nil;

    NSString *base = [_s.textureRoot stringByAppendingPathComponent:key];

    NSString *ciBase = CaseInsensitiveExistingPath(base);

    if(ciBase.length)
        return ciBase;

    if([[base pathExtension] length] == 0)
    {
        for(NSString *e in @[@"dds", @"png", @"pcx", @"jpg", @"jpeg", @"tga", @"bmp"])
        {
            NSString *p = [base stringByAppendingPathExtension:e];
            NSString *ci = CaseInsensitiveExistingPath(p);
                if(ci.length)
                    return ci;
        }
    }
    else
    {
        NSString *stem = [base stringByDeletingPathExtension];
        for(NSString *e in @[@"dds", @"png", @"pcx", @"jpg", @"jpeg", @"tga", @"bmp"])
        {
            NSString *p = [stem stringByAppendingPathExtension:e];
            NSString *ci = CaseInsensitiveExistingPath(p);
                if(ci.length)
                    return ci;
        }
    }

    return nil;
}

- (GLuint)textureForName:(NSString *)tn
{
    NSString *key = [tn ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSNumber *ct = _tex[key];
    if(ct)
        return ct.unsignedIntValue;

    NSString *fp = [self textureFileForName:key];
    GLuint tx = LoadTexture(fp);
    if(tx != 0)
        _tex[key] = @(tx);

    NSLog(@"[TEX] name='%@' root='%@' file='%@' gl=%u", key, _s.textureRoot, fp ?: @"<checker>", tx);
    return tx;
}

- (TextureMaterial *)materialForName:(NSString *)tn
{
    NSString *key = [tn ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!key.length)
        key = @"<empty>";

    TextureMaterial *m = _mat[key];
    if(m)
        return m;

    m = [TextureMaterial new];
    m.baseName = key;

    NSString *stem = key;
    NSString *ext = [stem pathExtension];
    if(ext.length)
        stem = [stem stringByDeletingPathExtension];

    NSString *diffuseName = key;
    NSString *glowName = [stem stringByAppendingString:@"-glow"];
    NSString *normalName = [stem stringByAppendingString:@"-normal"];
    NSString *shineName = [stem stringByAppendingString:@"-shine"];

    m.diffusePath = [self textureFileForName:diffuseName];
    m.glowPath = [self textureFileForName:glowName];
    m.normalPath = [self textureFileForName:normalName];
    m.shinePath = [self textureFileForName:shineName];

    m.diffuse = LoadTexture(m.diffusePath);
    if(m.glowPath.length)
        m.glow = LoadTexture(m.glowPath);
    if(m.normalPath.length)
        m.normal = LoadTexture(m.normalPath);
    if(m.shinePath.length)
        m.shine = LoadTexture(m.shinePath);

    _tex[diffuseName] = @(m.diffuse);
    if(m.glow)
        _tex[glowName] = @(m.glow);
    if(m.normal)
        _tex[normalName] = @(m.normal);
    if(m.shine)
        _tex[shineName] = @(m.shine);

    NSLog(@"[MAT] base='%@' diffuse='%@' glow='%@' normal='%@' shine='%@' ids=(%u,%u,%u,%u)",
          key,
          m.diffusePath ?: @"<checker>",
          m.glowPath ?: @"<none>",
          m.normalPath ?: @"<none>",
          m.shinePath ?: @"<none>",
          m.diffuse,
          m.glow,
          m.normal,
          m.shine);

    if(m.diffuse != 0)
        _mat[key] = m;
    return m;
}

- (void)buildVBOsForSub:(POFSub *)s mesh:(POFMesh *)pm
{
    s.vbosBuilt = YES;

    const POFTri *tri = (const POFTri *)s.tris.bytes;
    NSUInteger triCount = s.tris.length / sizeof(POFTri);

    if(triCount == 0) { s.vboBatches = [NSMutableData data]; return; }

    NSMutableArray *order = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for(NSUInteger t = 0; t < triCount; t++)
    {
        NSNumber *k = @(tri[t].texIndex);
        if(![seen containsObject:k]) { [seen addObject:k]; [order addObject:k]; }
    }

    NSMutableData *batches = [NSMutableData data];

    for(NSNumber *key in order)
    {
        int texIdx = key.intValue;

        // Vertex layout: [x,y,z, nx,ny,nz, u,v] — 8 floats, face normal per triangle
        NSMutableData *verts = [NSMutableData data];
        for(NSUInteger t = 0; t < triCount; t++)
        {
            if(tri[t].texIndex != texIdx) continue;

            // Face normal from cross product of the two edges
            float ex = tri[t].p[1].x - tri[t].p[0].x;
            float ey = tri[t].p[1].y - tri[t].p[0].y;
            float ez = tri[t].p[1].z - tri[t].p[0].z;
            float fx = tri[t].p[2].x - tri[t].p[0].x;
            float fy = tri[t].p[2].y - tri[t].p[0].y;
            float fz = tri[t].p[2].z - tri[t].p[0].z;
            float nx = ey*fz - ez*fy;
            float ny = ez*fx - ex*fz;
            float nz = ex*fy - ey*fx;
            float nl = sqrtf(nx*nx + ny*ny + nz*nz);
            if(nl > 1e-10f) { nx/=nl; ny/=nl; nz/=nl; }

            for(int k = 0; k < 3; k++)
            {
                float v[8] = {
                    tri[t].p[k].x, tri[t].p[k].y, tri[t].p[k].z,
                    nx, ny, nz,
                    tri[t].uv[k][0], tri[t].uv[k][1]
                };
                [verts appendBytes:v length:sizeof(v)];
            }
        }

        const GLsizei stride = 8 * sizeof(float);
        GLuint vao = 0, vbo = 0;
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)verts.length, verts.bytes, GL_STATIC_DRAW);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, (void *)0);                 // aPos
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, (void *)(3*sizeof(float))); // aNormal
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, stride, (void *)(6*sizeof(float))); // aUV
        glEnableVertexAttribArray(2);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindVertexArray(0);

        VBOBatch b;
        b.vao = vao; b.vbo = vbo;
        b.count    = (GLsizei)(verts.length / (NSUInteger)stride);
        b.texIndex = texIdx;
        [batches appendBytes:&b length:sizeof(b)];
    }

    s.vboBatches = batches;
}

- (void)drawSubobject:(POFSub *)s
                 mesh:(POFMesh *)pm
             children:(NSDictionary *)children
              elapsed:(float)elapsed
         reversedSubs:(NSSet *)reversedSubs
             modelMat:(Mat4)modelMat
{
    if([s.name rangeOfString:@"debris"  options:NSCaseInsensitiveSearch].location != NSNotFound ||
       [s.name rangeOfString:@"destroy" options:NSCaseInsensitiveSearch].location != NSNotFound)
        return;

    Mat4 subMat = Mat4Mul(modelMat, Mat4Translate(s.offset.x, s.offset.y, s.offset.z));

    if(s.rotates)
    {
        BOOL rev = reversedSubs && [reversedSubs containsObject:@(s.sid)];
        float angle = (rev ? -1.0f : 1.0f) * elapsed * s.spin;
        Mat4 rot;
        switch(s.movementAxis)
        {
            case 0:  rot = Mat4RotateX(angle); break;
            case 1:  rot = Mat4RotateZ(angle); break;
            case 2:  rot = Mat4RotateY(angle); break;
            default: rot = Mat4RotateY(angle); break;
        }
        subMat = Mat4Mul(subMat, rot);
    }

    if(!s.vbosBuilt)
        [self buildVBOsForSub:s mesh:pm];

    NSUInteger batchCount = s.vboBatches.length / sizeof(VBOBatch);

    if(batchCount > 0)
    {
        const VBOBatch *batches = (const VBOBatch *)s.vboBatches.bytes;

        glUseProgram(_shader);
        glUniformMatrix4fv(_uModel, 1, GL_FALSE, subMat.m);

        for(NSUInteger b = 0; b < batchCount; b++)
        {
            const VBOBatch *batch = &batches[b];

            NSString *polyTexName = s.tex ?: @"";
            if(batch->texIndex >= 0 && batch->texIndex < (int)pm.textures.count)
                polyTexName = pm.textures[(NSUInteger)batch->texIndex];

            TextureMaterial *mat = [self materialForName:polyTexName];

            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, mat.diffuse);
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_2D, mat.normal ? mat.normal : mat.diffuse);
            glActiveTexture(GL_TEXTURE2);
            glBindTexture(GL_TEXTURE_2D, mat.shine  ? mat.shine  : mat.diffuse);
            glActiveTexture(GL_TEXTURE0);
            glUniform1i(_uHasNormal, mat.normal != 0);
            glUniform1i(_uHasShine,  mat.shine  != 0);

            glBindVertexArray(batch->vao);
            glDrawArrays(GL_TRIANGLES, 0, batch->count);

            if(mat.glow)
            {
                glEnable(GL_BLEND);
                glBlendFunc(GL_SRC_ALPHA, GL_ONE);
                glDepthMask(GL_FALSE);
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, mat.glow);
                glUniform1i(_uEmissive, 1);
                glDrawArrays(GL_TRIANGLES, 0, batch->count);
                glUniform1i(_uEmissive, 0);
                glDepthMask(GL_TRUE);
                glDisable(GL_BLEND);
            }
        }

        glBindVertexArray(0);
        glUseProgram(0);
    }
    else
    {
        // No geometry — draw magenta placeholder cube
        Mat4 mvp = Mat4Mul(_proj, Mat4Mul(_view, subMat));
        glUseProgram(_flatShader);
        glUniformMatrix4fv(_uMVP, 1, GL_FALSE, mvp.m);
        glUniform1f(_uPointSize, 1.0f);
        glUniform4f(_uColorMul, 1, 0, 1, 1);
        glDisable(GL_CULL_FACE);
        glBindVertexArray(_cubeVAO);
        glDrawArrays(GL_TRIANGLES, 0, 36);
        glBindVertexArray(0);
        glEnable(GL_CULL_FACE);
        glUseProgram(0);
    }

    NSArray *kids = children[@(s.sid)];
    for(POFSub *child in kids)
        [self drawSubobject:child mesh:pm children:children elapsed:elapsed
               reversedSubs:reversedSubs modelMat:subMat];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;

    NSOpenGLContext *ctx = [self openGLContext];
    if(!ctx)
        return;
    [ctx makeCurrentContext];
    if(![NSOpenGLContext currentContext])
        return;

    if(!_glReady)
        [self _initGL];

    if(_drawing)
        return;

    _drawing = YES;

    NSTimeInterval n = [NSDate timeIntervalSinceReferenceDate];
    _e += (float)(n - _last);
    _last = n;

    glClearColor(0.01f, 0.01f, 0.03f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // View matrix: camera translation only (no rotation support yet)
    _view = Mat4Translate(-_s.cameraPosition.x,
                          -_s.cameraPosition.y,
                          -_s.cameraPosition.z);

    // Pre-compute flat-shader MVP (proj × view, no model transform)
    Mat4 flatMVP = Mat4Mul(_proj, _view);

    // --- Skybox load (once) ---
    if(!_skyboxLoaded)
    {
        _skyboxLoaded = YES;

        if(_s.skyboxName.length)
        {
            NSString *base = [_s.textureRoot stringByAppendingPathComponent:_s.skyboxName];
            NSString *fp = nil;

            for(NSString *ext in @[@"png", @"dds", @"pcx", @"jpg", @"jpeg"])
            {
                NSString *p = [base stringByAppendingPathExtension:ext];
                NSString *ci = CaseInsensitiveExistingPath(p);
                if(ci.length) { fp = ci; break; }
            }

            if(!fp && [[NSFileManager defaultManager] fileExistsAtPath:base])
                fp = base;

            if(fp)
                _skyboxTex = LoadTexture(fp);
            else
                NSLog(@"[SKY] not found: %@, using stars", base);
        }
    }

    // --- Stars (when no skybox) ---
    if(!_skyboxTex)
    {
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glUseProgram(_flatShader);
        glUniformMatrix4fv(_uMVP, 1, GL_FALSE, flatMVP.m);
        glUniform4f(_uColorMul, 1, 1, 1, 1);
        glBindVertexArray(_starsVAO);

        for(int pass = 0; pass < 3; pass++)
        {
            glUniform1f(_uPointSize, (float)(pass + 1) * 2.0f);
            glDrawArrays(GL_POINTS, pass * 500, 500);
        }

        glBindVertexArray(0);
        glUseProgram(0);

        glDisable(GL_BLEND);
        glEnable(GL_DEPTH_TEST);
    }

    // --- Debug axes ---
    {
        glUseProgram(_flatShader);
        glUniformMatrix4fv(_uMVP, 1, GL_FALSE, flatMVP.m);
        glUniform1f(_uPointSize, 1.0f);
        glUniform4f(_uColorMul, 1, 1, 1, 1);
        glBindVertexArray(_axesVAO);
        glDrawArrays(GL_LINES, 0, 6);
        glBindVertexArray(0);
        glUseProgram(0);
    }

    // --- Orbit loops ---
    if(_s.showLoops && _loopVAOs.count)
    {
        glDisable(GL_DEPTH_TEST);
        glUseProgram(_flatShader);
        glUniformMatrix4fv(_uMVP, 1, GL_FALSE, flatMVP.m);
        glUniform1f(_uPointSize, 1.0f);
        glUniform4f(_uColorMul, 1, 1, 1, 1);

        for(NSUInteger mi = 0; mi < _s.models.count && mi < _loopVAOs.count; mi++)
        {
            GLuint loopVAO = (GLuint)[[_loopVAOs objectAtIndex:mi] unsignedIntValue];
            if(!loopVAO) continue;
            glBindVertexArray(loopVAO);
            glDrawArrays(GL_LINE_LOOP, 0, 64);
        }

        glBindVertexArray(0);
        glUseProgram(0);
        glEnable(GL_DEPTH_TEST);
    }

    // --- Set per-frame mesh shader constants ---
    if(_shader)
    {
        // Light direction in view space (view is pure translation, so same as world space here)
        Vec3 sd = _s.sunDir;
        float ldv[3] = {
            _view.m[0]*sd.x + _view.m[4]*sd.y + _view.m[8]*sd.z,
            _view.m[1]*sd.x + _view.m[5]*sd.y + _view.m[9]*sd.z,
            _view.m[2]*sd.x + _view.m[6]*sd.y + _view.m[10]*sd.z
        };
        float len = sqrtf(ldv[0]*ldv[0] + ldv[1]*ldv[1] + ldv[2]*ldv[2]);
        if(len > 1e-6f) { ldv[0]/=len; ldv[1]/=len; ldv[2]/=len; }

        glUseProgram(_shader);
        glUniformMatrix4fv(_uView, 1, GL_FALSE, _view.m);
        glUniformMatrix4fv(_uProj, 1, GL_FALSE, _proj.m);
        glUniform3fv(_uLightDir, 1, ldv);
        glUseProgram(0);
    }

    // --- Models ---
    for(SceneModel *m in _s.models)
    {
        Vec3 p = m.position;
        Mat4 pathMat4 = Mat4Identity();
        BOOL usePathMat = NO;

        if(m.hasOvalPath && m.ovalRadius > 0)
        {
            float a = DegToRad(m.ovalAngleOffset + _e * m.ovalSpeedDegPerSec);
            Vec3 localOrbit, localTangent;
            if(m.ovalRev)
            {
                localOrbit   = (Vec3){cosf(a) * m.ovalRadius, 0.0f, -sinf(a) * m.ovalRadius};
                localTangent = (Vec3){-sinf(a), 0.0f, -cosf(a)};
            }
            else
            {
                localOrbit   = (Vec3){cosf(a) * m.ovalRadius, 0.0f, sinf(a) * m.ovalRadius};
                localTangent = (Vec3){-sinf(a), 0.0f, cosf(a)};
            }

            Vec3 worldOrbit   = V3RotXYZ(localOrbit,  m.ovalPlaneRot);
            Vec3 worldTangent = V3RotXYZ(localTangent, m.ovalPlaneRot);
            Vec3 worldUp      = V3RotXYZ((Vec3){0,1,0}, m.ovalPlaneRot);

            p.x += worldOrbit.x; p.y += worldOrbit.y; p.z += worldOrbit.z;

            Vec3 fwd   = V3Normalize(worldTangent);
            Vec3 right = V3Normalize(V3Cross(worldUp, fwd));
            Vec3 up    = V3Cross(fwd, right);

            pathMat4.m[0]=right.x; pathMat4.m[1]=right.y; pathMat4.m[2]=right.z;
            pathMat4.m[4]=up.x;    pathMat4.m[5]=up.y;    pathMat4.m[6]=up.z;
            pathMat4.m[8]=fwd.x;   pathMat4.m[9]=fwd.y;   pathMat4.m[10]=fwd.z;
            usePathMat = YES;
        }

        Mat4 model = Mat4Translate(p.x, p.y, p.z);
        if(usePathMat)                    model = Mat4Mul(model, pathMat4);
        if(m.rotationDeg.x != 0.0f)      model = Mat4Mul(model, Mat4RotateX(m.rotationDeg.x));
        if(m.rotationDeg.y != 0.0f)      model = Mat4Mul(model, Mat4RotateY(m.rotationDeg.y));
        if(m.rotationDeg.z != 0.0f)      model = Mat4Mul(model, Mat4RotateZ(m.rotationDeg.z));

        POFMesh *pm = _mesh[m.pofPath];
        if((id)pm == [NSNull null]) pm = nil;

        if(!pm && !_mesh[m.pofPath])
        {
            NSString *e = nil;
            pm = LoadPOFDetail0(m.pofPath, &e);
            _mesh[m.pofPath] = pm ?: (id)[NSNull null];
            NSLog(@"[POF] %@ -> %@", m.pofPath, e);
        }

        if(pm)
        {
            NSMutableDictionary *children = [NSMutableDictionary dictionary];
            NSMutableArray *roots = [NSMutableArray array];

            for(POFSub *sub in pm.subs)
            {
                if(sub.parent < 0)
                {
                    [roots addObject:sub];
                }
                else
                {
                    NSNumber *pk = @(sub.parent);
                    NSMutableArray *arr = children[pk];
                    if(!arr) { arr = [NSMutableArray array]; children[pk] = arr; }
                    [arr addObject:sub];
                }
            }

            if(roots.count == 0 && pm.subs.count > 0)
                [roots addObject:pm.subs[0]];

            NSSet *reversedSubs = nil;
            if(m.rotSync)
            {
                NSMutableDictionary *axisCount = [NSMutableDictionary dictionary];
                NSMutableSet *revSet = [NSMutableSet set];
                for(POFSub *sub in pm.subs)
                {
                    if(!sub.rotates) continue;
                    NSNumber *axis = @(sub.movementAxis);
                    NSUInteger idx = [axisCount[axis] unsignedIntegerValue];
                    BOOL reversed = (idx % 2 == 0) ? (BOOL)m.rotRev : (BOOL)!m.rotRev;
                    if(reversed) [revSet addObject:@(sub.sid)];
                    axisCount[axis] = @(idx + 1);
                }
                reversedSubs = revSet;
            }

            for(POFSub *root in roots)
                [self drawSubobject:root mesh:pm children:children elapsed:_e
                       reversedSubs:reversedSubs modelMat:model];
        }
        else
        {
            // Failed mesh load — red placeholder cube
            Mat4 mvp = Mat4Mul(_proj, Mat4Mul(_view, model));
            glUseProgram(_flatShader);
            glUniformMatrix4fv(_uMVP, 1, GL_FALSE, mvp.m);
            glUniform1f(_uPointSize, 1.0f);
            glUniform4f(_uColorMul, 1, 0.1f, 0.1f, 1);
            glDisable(GL_CULL_FACE);
            glBindVertexArray(_cubeVAO);
            glDrawArrays(GL_TRIANGLES, 0, 36);
            glBindVertexArray(0);
            glEnable(GL_CULL_FACE);
            glUseProgram(0);
        }
    }

    [[self openGLContext] flushBuffer];
    _drawing = NO;
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        NSString *sp = @"scene.txt";
        if(argc > 1)
            sp = [NSString stringWithUTF8String:argv[1]];

        NSError *e = nil;
        SceneDefinition *s = [SceneParser parseSceneAtPath:sp error:&e];

        if(!s)
        {
            fprintf(stderr, "scene load failed: %s\n", [[e description] UTF8String]);
            return 1;
        }

        NSLog(@"[SCENE] textureRoot=%@ camera=(%.2f %.2f %.2f) models=%lu",
              s.textureRoot,
              s.cameraPosition.x,
              s.cameraPosition.y,
              s.cameraPosition.z,
              (unsigned long)s.models.count);

        [NSApplication sharedApplication];

        NSWindow *w = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 1280, 720)
                      styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                        backing:NSBackingStoreBuffered
                          defer:NO];

        [w setTitle:@"POF Scene Viewer"];

        SpaceGLView *v = [[SpaceGLView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720)
                                                      scene:s];

        [w setContentView:v];
        [w makeFirstResponder:v];
        [w makeKeyAndOrderFront:nil];

        [NSApp run];
    }

    return 0;
}

