#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <dispatch/dispatch.h>

static int runHdiutil(NSArray<NSString *> *arguments, NSData **output, NSError **launchError) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/hdiutil"];
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    if (![task launchAndReturnError:launchError]) {
        return -1;
    }

    *output = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    return task.terminationStatus;
}

@interface OpenBurnWindowController : NSObject <NSWindowDelegate> {
    NSWindow *_window;
    NSTextField *_sourceField;
    NSTextField *_outputField;
    NSTextField *_imageField;
    NSTextField *_statusField;
    NSTextView *_logView;
    NSButton *_createButton;
    NSButton *_verifyButton;
    NSButton *_burnButton;
    NSButton *_refreshButton;
    BOOL _busy;
}

- (void)showWindow;

@end

@implementation OpenBurnWindowController

- (instancetype)init {
    self = [super init];
    if (self) {
        [self buildWindow];
    }
    return self;
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.alignment = NSTextAlignmentRight;
    return label;
}

- (NSStackView *)rowWithLabel:(NSString *)label control:(NSView *)control button:(NSButton *)button {
    NSStackView *row = [[NSStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 10;

    NSTextField *title = [self label:label];
    [NSLayoutConstraint activateConstraints:@[
        [title.widthAnchor constraintEqualToConstant:100],
        [control.heightAnchor constraintEqualToConstant:28]
    ]];
    [row addArrangedSubview:title];
    [row addArrangedSubview:control];
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    if (button) {
        [row addArrangedSubview:button];
    }
    return row;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)buildWindow {
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 620)
                                          styleMask:NSWindowStyleMaskTitled |
                                                    NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskMiniaturizable |
                                                    NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"OpenBurn";
    _window.minSize = NSMakeSize(620, 480);
    _window.delegate = self;

    NSView *content = _window.contentView;
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeWidth;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 14;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];

    NSTextField *heading = [NSTextField labelWithString:@"Optical Disc Tools"];
    heading.font = [NSFont boldSystemFontOfSize:22];
    [stack addArrangedSubview:heading];

    _sourceField = [[NSTextField alloc] init];
    _sourceField.placeholderString = @"Choose a folder to create an ISO from";
    NSButton *sourceButton = [self button:@"Choose Folder…" action:@selector(chooseSource:)];
    [stack addArrangedSubview:[self rowWithLabel:@"Source folder" control:_sourceField button:sourceButton]];

    _outputField = [[NSTextField alloc] init];
    _outputField.placeholderString = @"Choose where to save the new ISO";
    NSButton *outputButton = [self button:@"Save As…" action:@selector(chooseOutput:)];
    [stack addArrangedSubview:[self rowWithLabel:@"New image" control:_outputField button:outputButton]];

    _createButton = [self button:@"Create ISO" action:@selector(createImage:)];
    NSStackView *createRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [createRow addArrangedSubview:_createButton];
    createRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    createRow.alignment = NSLayoutAttributeCenterY;
    [stack addArrangedSubview:createRow];

    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];

    NSButton *imageButton = [self button:@"Choose Image…" action:@selector(chooseImage:)];
    _imageField = [[NSTextField alloc] init];
    _imageField.placeholderString = @"Select an ISO or disk image";
    [stack addArrangedSubview:[self rowWithLabel:@"Image file" control:_imageField button:imageButton]];

    _verifyButton = [self button:@"Verify Image" action:@selector(verifyImage:)];
    _burnButton = [self button:@"Burn to Disc…" action:@selector(confirmBurn:)];
    NSStackView *imageActions = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [imageActions addArrangedSubview:_verifyButton];
    [imageActions addArrangedSubview:_burnButton];
    imageActions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    imageActions.alignment = NSLayoutAttributeCenterY;
    imageActions.spacing = 10;
    [stack addArrangedSubview:imageActions];

    NSBox *driveSeparator = [NSBox new];
    driveSeparator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:driveSeparator];

    NSTextField *driveHeading = [NSTextField labelWithString:@"Optical drives"];
    driveHeading.font = [NSFont boldSystemFontOfSize:14];
    _refreshButton = [self button:@"Refresh Drives" action:@selector(refreshDrives:)];
    NSStackView *driveRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    [driveRow addArrangedSubview:driveHeading];
    [driveRow addArrangedSubview:_refreshButton];
    driveRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    driveRow.alignment = NSLayoutAttributeCenterY;
    driveRow.spacing = 12;
    [stack addArrangedSubview:driveRow];

    NSScrollView *logScrollView = [[NSScrollView alloc] init];
    logScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    logScrollView.hasVerticalScroller = YES;
    logScrollView.borderType = NSBezelBorder;
    _logView = [[NSTextView alloc] init];
    _logView.editable = NO;
    _logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _logView.textContainerInset = NSMakeSize(8, 8);
    logScrollView.documentView = _logView;
    [stack addArrangedSubview:logScrollView];
    [logScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    [logScrollView.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [logScrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                             forOrientation:NSLayoutConstraintOrientationVertical];
    [logScrollView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                   forOrientation:NSLayoutConstraintOrientationVertical];

    _statusField = [NSTextField labelWithString:@"Ready"];
    _statusField.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_statusField];

    [self appendLog:@"OpenBurn uses macOS hdiutil for ISO and disc operations."];
    [self appendLog:@"Refresh Drives to check which connected drives macOS supports."];
}

- (void)showWindow {
    [_window center];
    [_window makeKeyAndOrderFront:nil];
}

- (void)appendLog:(NSString *)text {
    NSString *existing = _logView.string ?: @"";
    _logView.string = [existing stringByAppendingFormat:@"%@\n", text];
    [_logView scrollRangeToVisible:NSMakeRange(_logView.string.length, 0)];
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    _busy = busy;
    _createButton.enabled = !busy;
    _verifyButton.enabled = !busy;
    _burnButton.enabled = !busy;
    _refreshButton.enabled = !busy;
    _statusField.stringValue = status;
}

- (void)runTool:(NSString *)tool arguments:(NSArray<NSString *> *)arguments
        success:(NSString *)success {
    if (_busy) {
        return;
    }
    [self setBusy:YES status:@"Working…"];
    [self appendLog:[NSString stringWithFormat:@"$ %@ %@", tool, [arguments componentsJoinedByString:@" "]]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *output = nil;
            NSError *launchError = nil;
            int exitCode = runHdiutil(arguments, &output, &launchError);
            NSString *result = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
            if (!result) {
                result = [[NSString alloc] initWithData:output encoding:NSISOLatin1StringEncoding] ?: @"";
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result.length > 0) {
                    [self appendLog:[result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                }
                if (exitCode == -1) {
                    [self appendLog:[NSString stringWithFormat:@"Could not start %@: %@", tool, launchError.localizedDescription]];
                    [self setBusy:NO status:@"Command could not be started"];
                } else if (exitCode == 0) {
                    [self appendLog:success];
                    [self setBusy:NO status:success];
                } else {
                    [self appendLog:[NSString stringWithFormat:@"Command failed (exit code %d).", exitCode]];
                    [self setBusy:NO status:@"Command failed; see output"];
                }
            });
        }
    });
}

- (void)chooseSource:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Choose Folder";
    if ([panel runModal] == NSModalResponseOK) {
        _sourceField.stringValue = panel.URL.path;
    }
}

- (void)chooseOutput:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"disc.iso";
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"iso"]];
    panel.prompt = @"Save ISO";
    if ([panel runModal] == NSModalResponseOK) {
        _outputField.stringValue = panel.URL.path;
    }
}

- (void)chooseImage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[
        [UTType typeWithFilenameExtension:@"iso"],
        [UTType typeWithFilenameExtension:@"dmg"],
        [UTType typeWithFilenameExtension:@"cdr"]
    ];
    panel.prompt = @"Choose Image";
    if ([panel runModal] == NSModalResponseOK) {
        _imageField.stringValue = panel.URL.path;
    }
}

- (void)createImage:(id)sender {
    NSString *source = _sourceField.stringValue;
    NSString *output = _outputField.stringValue;
    BOOL isDirectory = NO;
    if (source.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:source isDirectory:&isDirectory] || !isDirectory) {
        [self showError:@"Choose an existing source folder."];
        return;
    }
    if (output.length == 0) {
        [self showError:@"Choose a path for the new ISO image."];
        return;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:output]) {
        [self showError:@"The output file already exists. Choose a different path to avoid overwriting it."];
        return;
    }
    [self runTool:@"/usr/bin/hdiutil"
         arguments:@[@"makehybrid", @"-o", output, @"-iso", @"-joliet", source]
          success:@"ISO image created successfully."];
}

- (void)verifyImage:(id)sender {
    NSString *image = _imageField.stringValue;
    if (image.length == 0 || ![[NSFileManager defaultManager] isReadableFileAtPath:image]) {
        [self showError:@"Choose an existing, readable disk image."];
        return;
    }
    [self setBusy:YES status:@"Checking image…"];
    [self appendLog:[NSString stringWithFormat:@"$ hdiutil attach -readonly -nobrowse -noautoopen %@", image]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSData *attachOutput = nil;
            NSError *error = nil;
            int attachStatus = runHdiutil(@[@"attach", @"-readonly", @"-nobrowse", @"-noautoopen", image],
                                          &attachOutput, &error);
            NSString *output = [[NSString alloc] initWithData:attachOutput encoding:NSUTF8StringEncoding] ?: @"";
            NSString *device = nil;
            if (attachStatus == 0) {
                NSRegularExpression *expression =
                    [NSRegularExpression regularExpressionWithPattern:@"/dev/disk[0-9]+"
                                                              options:0
                                                                error:nil];
                NSTextCheckingResult *match =
                    [expression firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
                if (match) {
                    device = [output substringWithRange:[match rangeAtIndex:0]];
                }
            }

            NSData *detachOutput = nil;
            NSError *detachError = nil;
            int detachStatus = -1;
            if (device) {
                detachStatus = runHdiutil(@[@"detach", device], &detachOutput, &detachError);
            }
            NSString *detachText = [[NSString alloc] initWithData:detachOutput encoding:NSUTF8StringEncoding] ?: @"";

            dispatch_async(dispatch_get_main_queue(), ^{
                if (output.length > 0) {
                    [self appendLog:[output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                }
                if (attachStatus == -1) {
                    [self appendLog:[NSString stringWithFormat:@"Could not start hdiutil: %@", error.localizedDescription]];
                    [self setBusy:NO status:@"Image check could not be started"];
                } else if (attachStatus != 0) {
                    [self appendLog:[NSString stringWithFormat:@"Image check failed (exit code %d).", attachStatus]];
                    [self setBusy:NO status:@"Image is invalid or could not be mounted"];
                } else if (!device) {
                    [self appendLog:@"The image mounted, but macOS did not report a device to detach."];
                    [self setBusy:NO status:@"Image mounted; manual eject may be needed"];
                } else if (detachStatus != 0) {
                    if (detachText.length > 0) {
                        [self appendLog:[detachText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                    }
                    NSString *detail = detachStatus == -1 ? detachError.localizedDescription :
                                       [NSString stringWithFormat:@"exit code %d", detachStatus];
                    [self appendLog:[NSString stringWithFormat:@"Image was mounted at %@ but could not be detached (%@).", device, detail]];
                    [self setBusy:NO status:@"Image mounted; eject it manually"];
                } else {
                    [self appendLog:[NSString stringWithFormat:@"Image mounted read-only and detached successfully (%@).", device]];
                    [self setBusy:NO status:@"Image verification succeeded."];
                }
            });
        }
    });
}

- (void)confirmBurn:(id)sender {
    NSString *image = _imageField.stringValue;
    if (image.length == 0 || ![[NSFileManager defaultManager] isReadableFileAtPath:image]) {
        [self showError:@"Choose an existing, readable disk image."];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Burn this image to optical media?";
    alert.informativeText = @"Burning writes to a physical disc and may be irreversible. macOS will select the available supported drive.";
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Burn"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertSecondButtonReturn) {
            [self runTool:@"/usr/bin/hdiutil" arguments:@[@"burn", @"-verbose", image]
                  success:@"Burn completed successfully."];
        }
    }];
}

- (void)refreshDrives:(id)sender {
    [self runTool:@"/usr/bin/hdiutil" arguments:@[@"burn", @"-list"]
          success:@"Drive scan completed. Check the output for support status."];
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:_window completionHandler:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp terminate:nil];
}

@end

int main() {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];

        OpenBurnWindowController *controller = [[OpenBurnWindowController alloc] init];
        [controller showWindow];
        [application activateIgnoringOtherApps:YES];
        [application run];
    }
    return 0;
}
