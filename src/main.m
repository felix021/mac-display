#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef int (*DisplayServicesGetBrightnessFn)(CGDirectDisplayID display, float *brightness);
typedef int (*DisplayServicesSetBrightnessFn)(CGDirectDisplayID display, float brightness);

static const float kMinimumSavedBrightness = 0.05f;
static const float kFallbackRestoreBrightness = 0.6f;
static const NSTimeInterval kDebounceDelay = 0.75;

@interface Logger : NSObject
@property (nonatomic, assign) BOOL verbose;
@property (nonatomic, strong) NSDateFormatter *formatter;
- (instancetype)initWithVerbose:(BOOL)verbose;
- (void)info:(NSString *)message;
- (void)debug:(NSString *)message;
- (void)error:(NSString *)message;
@end

@implementation Logger
- (instancetype)initWithVerbose:(BOOL)verbose {
    self = [super init];
    if (self) {
        _verbose = verbose;
        _formatter = [[NSDateFormatter alloc] init];
        _formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    }
    return self;
}

- (void)logLevel:(NSString *)level message:(NSString *)message {
    NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n", [self.formatter stringFromDate:[NSDate date]], level, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data != nil) {
        fwrite(data.bytes, 1, data.length, stderr);
        fflush(stderr);
    }
}

- (void)info:(NSString *)message { [self logLevel:@"INFO" message:message]; }
- (void)error:(NSString *)message { [self logLevel:@"ERROR" message:message]; }
- (void)debug:(NSString *)message {
    if (self.verbose) {
        [self logLevel:@"DEBUG" message:message];
    }
}
@end

@interface StateStore : NSObject
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) Logger *logger;
- (instancetype)initWithLogger:(Logger *)logger error:(NSError **)error;
- (NSMutableDictionary *)loadState;
- (void)saveState:(NSDictionary *)state;
@end

@implementation StateStore
- (instancetype)initWithLogger:(Logger *)logger error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    _logger = logger;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *baseURL = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directoryURL = [baseURL URLByAppendingPathComponent:@"InternalDisplayAutoDim" isDirectory:YES];
    if (![fileManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }

    _fileURL = [directoryURL URLByAppendingPathComponent:@"state.json" isDirectory:NO];
    return self;
}

- (NSMutableDictionary *)loadState {
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
    if (data == nil) {
        return [@{@"dimmedByAgent": @NO} mutableCopy];
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error != nil) {
            [self.logger error:[NSString stringWithFormat:@"Failed to decode state: %@", error.localizedDescription]];
        }
        return [@{@"dimmedByAgent": @NO} mutableCopy];
    }

    return [object mutableCopy];
}

- (void)saveState:(NSDictionary *)state {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:&error];
    if (data == nil) {
        [self.logger error:[NSString stringWithFormat:@"Failed to encode state: %@", error.localizedDescription]];
        return;
    }

    if (![data writeToURL:self.fileURL options:NSDataWritingAtomic error:&error]) {
        [self.logger error:[NSString stringWithFormat:@"Failed to save state: %@", error.localizedDescription]];
    }
}
@end

@interface BrightnessController : NSObject
@property (nonatomic, assign) void *handle;
@property (nonatomic, assign) DisplayServicesGetBrightnessFn getBrightnessFn;
@property (nonatomic, assign) DisplayServicesSetBrightnessFn setBrightnessFn;
- (instancetype)initWithError:(NSError **)error;
- (float)brightnessForDisplay:(CGDirectDisplayID)displayID error:(NSError **)error;
- (BOOL)setBrightness:(float)value forDisplay:(CGDirectDisplayID)displayID error:(NSError **)error;
@end

@implementation BrightnessController
- (instancetype)initWithError:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    const char *frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices";
    _handle = dlopen(frameworkPath, RTLD_NOW);
    if (_handle == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"BrightnessController" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"Unable to load DisplayServices.framework"
            }];
        }
        return nil;
    }

    _getBrightnessFn = (DisplayServicesGetBrightnessFn)dlsym(_handle, "DisplayServicesGetBrightness");
    _setBrightnessFn = (DisplayServicesSetBrightnessFn)dlsym(_handle, "DisplayServicesSetBrightness");

    if (_getBrightnessFn == NULL || _setBrightnessFn == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"BrightnessController" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Unable to resolve DisplayServices brightness symbols"
            }];
        }
        return nil;
    }

    return self;
}

- (float)brightnessForDisplay:(CGDirectDisplayID)displayID error:(NSError **)error {
    float brightness = 0.0f;
    int result = self.getBrightnessFn(displayID, &brightness);
    if (result != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"BrightnessController" code:result userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"DisplayServicesGetBrightness failed with code %d", result]
            }];
        }
        return 0.0f;
    }

    return brightness;
}

- (BOOL)setBrightness:(float)value forDisplay:(CGDirectDisplayID)displayID error:(NSError **)error {
    float clamped = MIN(MAX(value, 0.0f), 1.0f);
    int result = self.setBrightnessFn(displayID, clamped);
    if (result != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"BrightnessController" code:result userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"DisplayServicesSetBrightness failed with code %d", result]
            }];
        }
        return NO;
    }

    return YES;
}
@end

@interface AgentOptions : NSObject
@property (nonatomic, assign) BOOL dryRun;
@property (nonatomic, assign) BOOL once;
@property (nonatomic, assign) BOOL restore;
@property (nonatomic, assign) BOOL verbose;
+ (instancetype)fromArgc:(int)argc argv:(const char *[])argv;
@end

@implementation AgentOptions
+ (instancetype)fromArgc:(int)argc argv:(const char *[])argv {
    AgentOptions *options = [[AgentOptions alloc] init];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"--dry-run"]) {
            options.dryRun = YES;
        } else if ([argument isEqualToString:@"--once"]) {
            options.once = YES;
        } else if ([argument isEqualToString:@"--restore"]) {
            options.restore = YES;
        } else if ([argument isEqualToString:@"--verbose"]) {
            options.verbose = YES;
        }
    }
    return options;
}
@end

@interface InternalDisplayAutoDimAgent : NSObject
@property (class, nonatomic, weak) InternalDisplayAutoDimAgent *sharedAgent;
@property (nonatomic, strong) AgentOptions *options;
@property (nonatomic, strong) Logger *logger;
@property (nonatomic, strong) StateStore *store;
@property (nonatomic, strong) BrightnessController *brightnessController;
@property (nonatomic, strong) NSMutableDictionary *state;
@property (nonatomic, strong) NSTimer *debounceTimer;
- (instancetype)initWithOptions:(AgentOptions *)options error:(NSError **)error;
- (void)run;
- (void)scheduleEvaluation;
- (void)evaluateForceRestore:(BOOL)forceRestore;
@end

static void DisplayReconfigurationCallback(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo);

@implementation InternalDisplayAutoDimAgent
static __weak InternalDisplayAutoDimAgent *_sharedAgent = nil;

+ (InternalDisplayAutoDimAgent *)sharedAgent { return _sharedAgent; }
+ (void)setSharedAgent:(InternalDisplayAutoDimAgent *)agent { _sharedAgent = agent; }

- (instancetype)initWithOptions:(AgentOptions *)options error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    _options = options;
    _logger = [[Logger alloc] initWithVerbose:options.verbose];
    _store = [[StateStore alloc] initWithLogger:_logger error:error];
    if (_store == nil) {
        return nil;
    }

    _brightnessController = [[BrightnessController alloc] initWithError:error];
    if (_brightnessController == nil) {
        return nil;
    }

    _state = [_store loadState];
    if (_state[@"dimmedByAgent"] == nil) {
        _state[@"dimmedByAgent"] = @NO;
    }

    return self;
}

- (void)run {
    [NSApplication sharedApplication];

    if (self.options.restore) {
        [self evaluateForceRestore:YES];
        return;
    }

    [self evaluateForceRestore:NO];
    if (self.options.once) {
        return;
    }

    InternalDisplayAutoDimAgent.sharedAgent = self;
    CGError result = CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallback, NULL);
    if (result != kCGErrorSuccess) {
        [self.logger error:[NSString stringWithFormat:@"Unable to register display callback: %d", result]];
        exit(1);
    }

    [self.logger info:@"Watching display changes"];
    [[NSRunLoop mainRunLoop] run];
}

- (void)scheduleEvaluation {
    [self.debounceTimer invalidate];
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:kDebounceDelay
                                                          repeats:NO
                                                            block:^(__unused NSTimer *timer) {
        [self evaluateForceRestore:NO];
    }];
}

- (NSString *)actionDescription:(NSString *)action {
    return self.options.dryRun ? [NSString stringWithFormat:@"[dry-run] %@", action] : action;
}

- (NSArray<NSNumber *> *)onlineDisplaysWithError:(NSError **)error {
    uint32_t count = 0;
    CGError countResult = CGGetOnlineDisplayList(0, NULL, &count);
    if (countResult != kCGErrorSuccess) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"InternalDisplayAutoDimAgent" code:countResult userInfo:@{
                NSLocalizedDescriptionKey: @"CGGetOnlineDisplayList failed while counting displays"
            }];
        }
        return nil;
    }

    CGDirectDisplayID displays[count];
    CGError listResult = CGGetOnlineDisplayList(count, displays, &count);
    if (listResult != kCGErrorSuccess) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"InternalDisplayAutoDimAgent" code:listResult userInfo:@{
                NSLocalizedDescriptionKey: @"CGGetOnlineDisplayList failed while reading displays"
            }];
        }
        return nil;
    }

    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        [result addObject:@(displays[i])];
    }
    return result;
}

- (NSNumber *)builtInDisplayIDWithError:(NSError **)error {
    NSArray<NSNumber *> *displays = [self onlineDisplaysWithError:error];
    for (NSNumber *displayNumber in displays) {
        if (CGDisplayIsBuiltin(displayNumber.unsignedIntValue) != 0) {
            return displayNumber;
        }
    }
    return nil;
}

- (NSUInteger)externalDisplayCountExcludingBuiltIn:(CGDirectDisplayID)builtInDisplay error:(NSError **)error {
    NSArray<NSNumber *> *displays = [self onlineDisplaysWithError:error];
    NSUInteger count = 0;
    for (NSNumber *displayNumber in displays) {
        CGDirectDisplayID displayID = displayNumber.unsignedIntValue;
        if (displayID != builtInDisplay && CGDisplayIsBuiltin(displayID) == 0) {
            count += 1;
        }
    }
    return count;
}

- (void)dimIfNeededForDisplay:(CGDirectDisplayID)displayID currentBrightness:(float)currentBrightness {
    BOOL dimmedByAgent = [self.state[@"dimmedByAgent"] boolValue];
    NSNumber *savedBrightness = self.state[@"savedBrightness"];

    NSMutableDictionary *nextState = [self.state mutableCopy];
    if (!dimmedByAgent && currentBrightness > kMinimumSavedBrightness) {
        nextState[@"savedBrightness"] = @(currentBrightness);
        [self.logger info:[NSString stringWithFormat:@"Saved brightness %.3f", currentBrightness]];
    } else if (savedBrightness == nil && currentBrightness > kMinimumSavedBrightness) {
        nextState[@"savedBrightness"] = @(currentBrightness);
    }

    if (dimmedByAgent && currentBrightness <= 0.001f) {
        [self.logger debug:@"Built-in display already dimmed by agent"];
        return;
    }

    [self.logger info:[self actionDescription:@"Setting built-in display brightness to 0"]];
    if (!self.options.dryRun) {
        NSError *error = nil;
        if (![self.brightnessController setBrightness:0.0f forDisplay:displayID error:&error]) {
            [self.logger error:[NSString stringWithFormat:@"Failed to dim built-in display: %@", error.localizedDescription]];
            return;
        }
    }

    if (!self.options.dryRun) {
        nextState[@"dimmedByAgent"] = @YES;
        self.state = nextState;
        [self.store saveState:self.state];
    }
}

- (void)restoreIfNeededForDisplay:(CGDirectDisplayID)displayID currentBrightness:(float)currentBrightness {
    BOOL dimmedByAgent = [self.state[@"dimmedByAgent"] boolValue];
    if (!dimmedByAgent) {
        [self.logger debug:@"No restore needed"];
        return;
    }

    NSNumber *savedBrightness = self.state[@"savedBrightness"];
    float targetBrightness = savedBrightness != nil ? savedBrightness.floatValue : kFallbackRestoreBrightness;
    if (targetBrightness < kMinimumSavedBrightness) {
        targetBrightness = kMinimumSavedBrightness;
    }

    [self.logger info:[self actionDescription:[NSString stringWithFormat:@"Restoring built-in display brightness to %.3f", targetBrightness]]];
    if (!self.options.dryRun) {
        NSError *error = nil;
        if (![self.brightnessController setBrightness:targetBrightness forDisplay:displayID error:&error]) {
            [self.logger error:[NSString stringWithFormat:@"Failed to restore built-in display: %@", error.localizedDescription]];
            return;
        }
    }

    if (!self.options.dryRun) {
        NSMutableDictionary *nextState = [self.state mutableCopy];
        nextState[@"dimmedByAgent"] = @NO;
        if (currentBrightness > kMinimumSavedBrightness) {
            nextState[@"savedBrightness"] = @(currentBrightness);
        }
        self.state = nextState;
        [self.store saveState:self.state];
    }
}

- (void)evaluateForceRestore:(BOOL)forceRestore {
    NSError *error = nil;
    NSNumber *builtInDisplayNumber = [self builtInDisplayIDWithError:&error];
    if (builtInDisplayNumber == nil) {
        NSString *message = error != nil ? error.localizedDescription : @"No built-in display found";
        [self.logger error:message];
        return;
    }

    CGDirectDisplayID builtInDisplay = builtInDisplayNumber.unsignedIntValue;
    NSUInteger externalCount = [self externalDisplayCountExcludingBuiltIn:builtInDisplay error:&error];
    if (error != nil) {
        [self.logger error:error.localizedDescription];
        return;
    }

    float currentBrightness = [self.brightnessController brightnessForDisplay:builtInDisplay error:&error];
    if (error != nil) {
        [self.logger error:error.localizedDescription];
        return;
    }

    [self.logger debug:[NSString stringWithFormat:@"Built-in display %u brightness=%.3f externalCount=%lu state=%@", builtInDisplay, currentBrightness, (unsigned long)externalCount, self.state]];

    if (forceRestore || externalCount == 0) {
        [self restoreIfNeededForDisplay:builtInDisplay currentBrightness:currentBrightness];
    } else {
        [self dimIfNeededForDisplay:builtInDisplay currentBrightness:currentBrightness];
    }
}
@end

static void DisplayReconfigurationCallback(__unused CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, __unused void *userInfo) {
    if ((flags & kCGDisplayBeginConfigurationFlag) != 0) {
        return;
    }

    InternalDisplayAutoDimAgent *agent = InternalDisplayAutoDimAgent.sharedAgent;
    if (agent == nil) {
        return;
    }

    [agent.logger debug:[NSString stringWithFormat:@"Display reconfiguration received: %u", flags]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [agent scheduleEvaluation];
    });
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        AgentOptions *options = [AgentOptions fromArgc:argc argv:argv];
        NSError *error = nil;
        InternalDisplayAutoDimAgent *agent = [[InternalDisplayAutoDimAgent alloc] initWithOptions:options error:&error];
        if (agent == nil) {
            NSString *message = [NSString stringWithFormat:@"Startup failed: %@\n", error.localizedDescription];
            NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
            fwrite(data.bytes, 1, data.length, stderr);
            return 1;
        }

        [agent run];
        return 0;
    }
}
