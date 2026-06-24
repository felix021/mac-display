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

    return [self runTask:@"/bin/launchctl" arguments:@[@"kickstart", @"-k", [self guiDomainTarget]] captureOutput:nil error:error];
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

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic, strong) AgentController *controller;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *statusItemLabel;
@property (nonatomic, strong) NSMenuItem *enableItem;
@property (nonatomic, strong) NSMenuItem *disableItem;
@property (nonatomic, strong) NSMenuItem *restoreItem;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.controller = [[AgentController alloc] init];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"MD";
    self.statusItem.button.toolTip = @"Mac Display Control";

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

- (void)refreshMenuState {
    BOOL installed = [self.controller isInstalled];
    BOOL enabled = installed && [self.controller isEnabled];

    if (!installed) {
        self.statusItemLabel.title = @"Agent not installed";
        self.enableItem.enabled = NO;
        self.disableItem.enabled = NO;
        self.restoreItem.enabled = NO;
        self.statusItem.button.title = @"MD?";
        self.statusItem.button.toolTip = @"Mac Display Control: agent not installed";
        return;
    }

    self.statusItemLabel.title = enabled ? @"Auto dimming is enabled" : @"Auto dimming is disabled";
    self.enableItem.enabled = !enabled;
    self.disableItem.enabled = enabled;
    self.restoreItem.enabled = YES;
    self.statusItem.button.title = enabled ? @"MD" : @"MD Off";
    self.statusItem.button.toolTip = enabled ? @"Mac Display Control: enabled" : @"Mac Display Control: disabled";
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

- (void)enableAgent:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![self.controller enable:&error]) {
        [self presentError:error];
    }
    [self refreshMenuState];
}

- (void)disableAgent:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![self.controller disable:&error]) {
        [self presentError:error];
    }
    [self refreshMenuState];
}

- (void)restoreBrightness:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![self.controller restoreBrightness:&error]) {
        [self presentError:error];
    }
    [self refreshMenuState];
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
