#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <unistd.h>

@interface AgentController : NSObject
@property (nonatomic, copy, readonly) NSString *label;
@property (nonatomic, copy, readonly) NSString *plistPath;
@property (nonatomic, copy, readonly) NSString *installedBinary;
@property (nonatomic, copy, readonly) NSString *logPath;
- (BOOL)isInstalled;
- (BOOL)isEnabled;
- (BOOL)enable:(NSError **)error;
- (BOOL)disable:(NSError **)error;
- (BOOL)restoreBrightness:(NSError **)error;
- (void)openLog;
@end

@implementation AgentController
- (instancetype)init {
    self = [super init];
    if (self) {
        _label = @"com.felix021.macdisplay";
        _plistPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.felix021.macdisplay.plist"];
        _installedBinary = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MacDisplay/MacDisplayAgent"];
        _logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MacDisplay/agent.log"];
    }
    return self;
}

- (NSString *)guiDomainTarget {
    return [NSString stringWithFormat:@"gui/%d/%@", getuid(), self.label];
}

- (NSString *)guiDomain {
    return [NSString stringWithFormat:@"gui/%d", getuid()];
}

- (BOOL)isInstalled {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:self.plistPath] && [fileManager isExecutableFileAtPath:self.installedBinary];
}

- (BOOL)runTask:(NSString *)launchPath
      arguments:(NSArray<NSString *> *)arguments
  captureOutput:(NSString * __autoreleasing *)output
          error:(NSError **)error {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MacDisplayControl" code:1 userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Failed to launch helper task"
            }];
        }
        return NO;
    }

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *combinedOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (output != NULL) {
        *output = combinedOutput;
    }

    if (task.terminationStatus != 0) {
        if (error != NULL) {
            NSString *message = combinedOutput.length > 0 ? combinedOutput : [NSString stringWithFormat:@"%@ exited with status %d", launchPath, task.terminationStatus];
            *error = [NSError errorWithDomain:@"MacDisplayControl" code:task.terminationStatus userInfo:@{
                NSLocalizedDescriptionKey: message
            }];
        }
        return NO;
    }

    return YES;
}

- (BOOL)isEnabled {
    if (![self isInstalled]) {
        return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"print", [self guiDomainTarget]];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (__unused NSException *exception) {
        return NO;
    }

    return task.terminationStatus == 0;
}

- (BOOL)enable:(NSError **)error {
    if (![self isInstalled]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MacDisplayControl" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"mac-display is not installed yet. Run install.sh first."
            }];
        }
        return NO;
    }

    if ([self isEnabled]) {
        return YES;
    }

    if (![self runTask:@"/bin/launchctl" arguments:@[@"bootstrap", [self guiDomain], self.plistPath] captureOutput:nil error:error]) {
        return NO;
    }

    return YES;
}

- (BOOL)disable:(NSError **)error {
    if (![self isInstalled]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MacDisplayControl" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"mac-display is not installed yet. Run install.sh first."
            }];
        }
        return NO;
    }

    if (![self restoreBrightness:nil]) {
        // Ignore restore failure here, we'll still try to disable the agent.
    }

    if (![self isEnabled]) {
        return YES;
    }

    return [self runTask:@"/bin/launchctl" arguments:@[@"bootout", [self guiDomain], self.plistPath] captureOutput:nil error:error];
}

- (BOOL)restoreBrightness:(NSError **)error {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:self.installedBinary]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MacDisplayControl" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"Installed agent binary is missing."
            }];
        }
        return NO;
    }

    return [self runTask:self.installedBinary arguments:@[@"--restore", @"--once"] captureOutput:nil error:error];
}

- (void)openLog {
    NSString *pathToOpen = self.logPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:pathToOpen]) {
        pathToOpen = [self.logPath stringByDeletingLastPathComponent];
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:pathToOpen]];
}
@end

typedef NS_ENUM(NSInteger, MacDisplayLogoState) {
    MacDisplayLogoStateEnabled,
    MacDisplayLogoStateDisabled,
    MacDisplayLogoStateBusy,
    MacDisplayLogoStateMissing,
};

static void DrawRoundedRect(NSRect rect, CGFloat radius) {
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

static void StrokeRoundedRect(NSRect rect, CGFloat radius, CGFloat lineWidth) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    path.lineWidth = lineWidth;
    [path stroke];
}

static void DrawMacDisplayLogo(NSRect rect, MacDisplayLogoState state, BOOL appIcon) {
    CGFloat scale = MIN(rect.size.width, rect.size.height) / 24.0;
    NSRect box = NSMakeRect(rect.origin.x + (rect.size.width - 24.0 * scale) / 2.0,
                           rect.origin.y + (rect.size.height - 24.0 * scale) / 2.0,
                           24.0 * scale,
                           24.0 * scale);

    NSColor *strokeColor = appIcon ? [NSColor colorWithCalibratedWhite:0.10 alpha:1.0] : [NSColor labelColor];
    NSColor *monitorFill = appIcon ? [NSColor colorWithCalibratedWhite:0.94 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.92 alpha:0.95];
    NSColor *monitorInset = appIcon ? [NSColor colorWithCalibratedWhite:0.18 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.18 alpha:0.9];
    NSColor *macBody = appIcon ? [NSColor colorWithCalibratedWhite:0.78 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.70 alpha:0.95];
    NSColor *macScreen = [NSColor colorWithCalibratedWhite:0.18 alpha:1.0];

    if (state == MacDisplayLogoStateEnabled) {
        macScreen = appIcon ? [NSColor colorWithCalibratedRed:0.46 green:0.83 blue:1.00 alpha:1.0]
                            : [NSColor colorWithCalibratedRed:0.34 green:0.78 blue:1.00 alpha:1.0];
    } else if (state == MacDisplayLogoStateBusy) {
        macScreen = [NSColor colorWithCalibratedRed:1.00 green:0.72 blue:0.28 alpha:1.0];
    } else if (state == MacDisplayLogoStateMissing) {
        macScreen = [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
    }

    if (appIcon) {
        NSGradient *background = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.09 green:0.13 blue:0.18 alpha:1.0]
                                                               endingColor:[NSColor colorWithCalibratedRed:0.24 green:0.31 blue:0.38 alpha:1.0]];
        [background drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:rect xRadius:rect.size.width * 0.22 yRadius:rect.size.height * 0.22] angle:90.0];
        strokeColor = [NSColor colorWithCalibratedWhite:0.06 alpha:1.0];
    }

    CGFloat lineWidth = MAX(1.0, 1.45 * scale);

    NSRect macScreenRect = NSMakeRect(box.origin.x + 2.0 * scale, box.origin.y + 7.2 * scale, 10.8 * scale, 8.8 * scale);
    NSRect macBaseRect = NSMakeRect(box.origin.x + 1.2 * scale, box.origin.y + 5.1 * scale, 12.5 * scale, 2.1 * scale);
    NSRect monitorRect = NSMakeRect(box.origin.x + 6.3 * scale, box.origin.y + 4.1 * scale, 15.4 * scale, 13.8 * scale);
    NSRect monitorScreen = NSInsetRect(monitorRect, 2.1 * scale, 2.1 * scale);
    NSRect standRect = NSMakeRect(box.origin.x + 12.7 * scale, box.origin.y + 2.5 * scale, 2.6 * scale, 2.2 * scale);
    NSRect footRect = NSMakeRect(box.origin.x + 10.0 * scale, box.origin.y + 1.7 * scale, 8.1 * scale, 1.6 * scale);

    [macBody setFill];
    DrawRoundedRect(macBaseRect, 0.8 * scale);
    [strokeColor setStroke];
    StrokeRoundedRect(macBaseRect, 0.8 * scale, lineWidth * 0.65);

    [macScreen setFill];
    DrawRoundedRect(macScreenRect, 1.6 * scale);
    [strokeColor setStroke];
    StrokeRoundedRect(macScreenRect, 1.6 * scale, lineWidth);

    [monitorFill setFill];
    DrawRoundedRect(monitorRect, 2.2 * scale);
    [strokeColor setStroke];
    StrokeRoundedRect(monitorRect, 2.2 * scale, lineWidth);

    [monitorInset setFill];
    DrawRoundedRect(monitorScreen, 1.1 * scale);

    [macBody setFill];
    DrawRoundedRect(standRect, 0.5 * scale);
    DrawRoundedRect(footRect, 0.8 * scale);
    [strokeColor setStroke];
    StrokeRoundedRect(footRect, 0.8 * scale, lineWidth * 0.65);
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic, strong) AgentController *controller;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *statusItemLabel;
@property (nonatomic, strong) NSMenuItem *enableItem;
@property (nonatomic, strong) NSMenuItem *disableItem;
@property (nonatomic, strong) NSMenuItem *restoreItem;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, copy) NSString *busyMessage;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.controller = [[AgentController alloc] init];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [self updateStatusIconForState:@"initial"];

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Mac Display"];
    menu.delegate = self;

    self.statusItemLabel = [[NSMenuItem alloc] initWithTitle:@"Checking status..." action:nil keyEquivalent:@""];
    self.statusItemLabel.enabled = NO;
    [menu addItem:self.statusItemLabel];
    [menu addItem:[NSMenuItem separatorItem]];

    self.enableItem = [[NSMenuItem alloc] initWithTitle:@"Enable Auto Dimming" action:@selector(enableAgent:) keyEquivalent:@""];
    self.enableItem.target = self;
    [menu addItem:self.enableItem];

    self.disableItem = [[NSMenuItem alloc] initWithTitle:@"Disable Auto Dimming" action:@selector(disableAgent:) keyEquivalent:@""];
    self.disableItem.target = self;
    [menu addItem:self.disableItem];

    self.restoreItem = [[NSMenuItem alloc] initWithTitle:@"Restore Built-in Brightness" action:@selector(restoreBrightness:) keyEquivalent:@""];
    self.restoreItem.target = self;
    [menu addItem:self.restoreItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *openLogItem = [[NSMenuItem alloc] initWithTitle:@"Open Agent Log" action:@selector(openLog:) keyEquivalent:@""];
    openLogItem.target = self;
    [menu addItem:openLogItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Menu App" action:@selector(quitApp:) keyEquivalent:@""];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
    [self refreshMenuState];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    [self refreshMenuState];
}

- (NSImage *)statusImageForState:(NSString *)state {
    NSString *description = @"Mac Display Control";
    NSString *resourceName = @"MacDisplayTrayDisabled";

    if ([state isEqualToString:@"enabled"]) {
        resourceName = @"MacDisplayTrayEnabled";
        description = @"Mac Display Control enabled";
    } else if ([state isEqualToString:@"disabled"]) {
        resourceName = @"MacDisplayTrayDisabled";
        description = @"Mac Display Control disabled";
    } else if ([state isEqualToString:@"busy"]) {
        resourceName = @"MacDisplayTrayEnabled";
        description = self.busyMessage ?: @"Mac Display Control working";
    } else if ([state isEqualToString:@"missing"]) {
        resourceName = @"MacDisplayTrayDisabled";
        description = @"Mac Display Control not installed";
    }

    NSString *imagePath = [[NSBundle mainBundle] pathForResource:resourceName ofType:@"png"];
    NSImage *image = imagePath != nil ? [[NSImage alloc] initWithContentsOfFile:imagePath] : nil;
    if (image == nil) {
        self.statusItem.button.title = @"MD";
        return nil;
    }

    image.size = NSMakeSize(22.0, 22.0);
    [image setAccessibilityDescription:description];
    image.template = NO;
    self.statusItem.button.title = @"";
    return image;
}

- (void)updateStatusIconForState:(NSString *)state {
    NSStatusBarButton *button = self.statusItem.button;
    if (button == nil) {
        return;
    }

    NSImage *image = [self statusImageForState:state];
    button.image = image;
    if (image == nil && button.title.length == 0) {
        button.title = @"MD";
    }
}

- (void)refreshMenuState {
    if (self.busy) {
        self.statusItemLabel.title = self.busyMessage ?: @"Working...";
        self.enableItem.enabled = NO;
        self.disableItem.enabled = NO;
        self.restoreItem.enabled = NO;
        self.statusItem.button.toolTip = self.busyMessage ?: @"Mac Display Control is working";
        [self updateStatusIconForState:@"busy"];
        return;
    }

    BOOL installed = [self.controller isInstalled];
    BOOL enabled = installed && [self.controller isEnabled];

    if (!installed) {
        self.statusItemLabel.title = @"Agent not installed";
        self.enableItem.enabled = NO;
        self.disableItem.enabled = NO;
        self.restoreItem.enabled = NO;
        self.statusItem.button.toolTip = @"Mac Display Control: agent not installed";
        [self updateStatusIconForState:@"missing"];
        return;
    }

    self.statusItemLabel.title = enabled ? @"Auto dimming is enabled" : @"Auto dimming is disabled";
    self.enableItem.enabled = !enabled;
    self.disableItem.enabled = enabled;
    self.restoreItem.enabled = YES;
    self.statusItem.button.toolTip = enabled ? @"Mac Display Control: enabled" : @"Mac Display Control: disabled";
    [self updateStatusIconForState:enabled ? @"enabled" : @"disabled"];
}

- (void)presentError:(NSError *)error {
    if (error == nil) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Mac Display Control";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)runAsyncActionWithBusyMessage:(NSString *)busyMessage block:(BOOL (^)(NSError **error))block {
    if (self.busy) {
        return;
    }

    self.busy = YES;
    self.busyMessage = busyMessage;
    [self refreshMenuState];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL success = block(&error);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.busyMessage = nil;
            [self refreshMenuState];
            if (!success) {
                [self presentError:error];
            }
        });
    });
}

- (void)enableAgent:(id)sender {
    (void)sender;
    [self runAsyncActionWithBusyMessage:@"Enabling auto dimming..." block:^BOOL(NSError **error) {
        return [self.controller enable:error];
    }];
}

- (void)disableAgent:(id)sender {
    (void)sender;
    [self runAsyncActionWithBusyMessage:@"Disabling auto dimming..." block:^BOOL(NSError **error) {
        return [self.controller disable:error];
    }];
}

- (void)restoreBrightness:(id)sender {
    (void)sender;
    [self runAsyncActionWithBusyMessage:@"Restoring built-in brightness..." block:^BOOL(NSError **error) {
        return [self.controller restoreBrightness:error];
    }];
}

- (void)openLog:(id)sender {
    (void)sender;
    [self.controller openLog];
}

- (void)quitApp:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
