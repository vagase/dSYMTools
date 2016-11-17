//
//  MainWindowViewController.m
//  CustomModalWindow
//
//  Created by answer on 7/26/16.
//  Copyright © 2016 answer. All rights reserved.
//

#import "MainWindowViewController.h"
#import "AboutWindowController.h"
#import "ArchiveInfo.h"
#import "UUIDInfo.h"
#import "ArchiveFilesScrollView.h"


@interface MainWindowViewController ()<NSTableViewDelegate, NSTableViewDataSource, NSDraggingDestination>


@property (strong) AboutWindowController *aboutWindowController;

/**
 *  显示 archive 文件的 tableView
 */
@property (weak) IBOutlet NSTableView *archiveFilesTableView;

/**
 *  存放 radio 的 box
 */
@property (weak) IBOutlet NSBox *radioBox;

/**
 *  archive 文件信息数组
 */
@property (copy) NSMutableArray<ArchiveInfo *> *archiveFilesInfo;

/**
 *  选中的 archive 文件信息
 */
@property (strong) ArchiveInfo *selectedArchiveInfo;

/**
 * 选中的 UUID 信息
 */
@property (strong) UUIDInfo *selectedUUIDInfo;

/**
 *  显示选中的 CPU 类型对应可执行文件的 UUID
 */
@property (weak) IBOutlet NSTextField *selectedUUIDLabel;

/**
 *  显示默认的 Slide Address
 */
@property (weak) IBOutlet NSTextField *defaultSlideAddressLabel;

/**
 *  显示错误内存地址
 */
@property (unsafe_unretained) IBOutlet NSTextView *errorMemoryAddressView;

/**
 *  错误信息
 */
@property (unsafe_unretained) IBOutlet NSTextView *errorMessageView;



@property (weak) IBOutlet ArchiveFilesScrollView *archiveFilesScrollView;

@property (weak) IBOutlet NSProgressIndicator *progressIndicator;

@property (weak) IBOutlet NSTextField *timeCostLabel;

@end

@implementation MainWindowViewController


- (void)windowDidLoad{
    [super windowDidLoad];
    
    [self.window registerForDraggedTypes:@[NSColorPboardType, NSFilenamesPboardType]];
    
    self.archiveFilesTableView.doubleAction = @selector(doubleActionMethod);

    NSArray *archiveFilePaths = [self allDSYMFilePath];
    [self handleArchiveFileWithPath:archiveFilePaths];
    
    self.errorMemoryAddressView.font = [NSFont fontWithName:@"Monaco" size:12];
    self.errorMessageView.font = [NSFont fontWithName:@"Monaco" size:12];
}

/**
 *  处理给定archive文件路径，获取 archiveinfo 对象
 *
 *  @param archiveFilePaths archvie 文件路径
 */
- (void)handleArchiveFileWithPath:(NSArray *)archiveFilePaths {
    _archiveFilesInfo = [NSMutableArray arrayWithCapacity:1];
    for(NSString *archivePath in archiveFilePaths){
        ArchiveInfo *archiveInfo = [[ArchiveInfo alloc] init];
        archiveInfo.archiveFilePath = archivePath;
        NSString *fileName = archivePath.lastPathComponent;
        //如果不是 xcarchive 文件路径则继续循环
        if (![fileName hasSuffix:@".xcarchive"]){
            continue;
        }
        archiveInfo.archiveFileName = fileName;
        [_archiveFilesInfo addObject:archiveInfo];
    }
    [self extraDSYMInfoFromArchiveInfo:_archiveFilesInfo];

    [self.archiveFilesTableView reloadData];
}

/**
 *  从 archive 文件中获取 dsym 文件信息
 *
 *  @param archiveFilesPath archive info 对象
 */
- (void)extraDSYMInfoFromArchiveInfo:(NSArray *)archiveFilesPath {

    //匹配 () 里面内容
    NSString *pattern = @"(?<=\\()[^}]*(?=\\))";
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];

    for(ArchiveInfo *archiveInfo in archiveFilesPath){
        NSString *dSYMsDirectoryPath = [NSString stringWithFormat:@"%@/dSYMs", archiveInfo.archiveFilePath];
        NSArray *keys = @[@"NSURLPathKey",@"NSURLFileResourceTypeKey",@"NSURLIsDirectoryKey",@"NSURLIsPackageKey"];
        NSArray *dSYMSubFiles= [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:dSYMsDirectoryPath] includingPropertiesForKeys:keys options:(NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants) error:nil];
        for(NSURL *fileURLs in dSYMSubFiles){
            if ([[fileURLs.relativePath lastPathComponent] hasSuffix:@"dSYM"]){
                archiveInfo.dSYMFilePath = fileURLs.relativePath;
                archiveInfo.dSYMFileName = fileURLs.relativePath.lastPathComponent;
            }
        }
        NSString *commandString = [NSString stringWithFormat:@"dwarfdump --uuid \"%@\"",archiveInfo.dSYMFilePath];
        NSString *uuidsString = [self runCommand:commandString];
        NSArray *uuids = [uuidsString componentsSeparatedByString:@"\n"];

        NSMutableArray *uuidInfos = [NSMutableArray arrayWithCapacity:1];
        for(NSString *uuidString in uuids){
            NSArray* match = [reg matchesInString:uuidString options:NSMatchingReportCompletion range:NSMakeRange(0, [uuidString length])];
            if (match.count == 0) {
                continue;
            }
            for (NSTextCheckingResult *result in match) {
                NSRange range = [result range];
                UUIDInfo *uuidInfo = [[UUIDInfo alloc] init];
                uuidInfo.arch = [uuidString substringWithRange:range];
                uuidInfo.uuid = [uuidString substringWithRange:NSMakeRange(6, range.location-6-2)];
                uuidInfo.executableFilePath = [uuidString substringWithRange:NSMakeRange(range.location+range.length+2, [uuidString length]-(range.location+range.length+2))];
                [uuidInfos addObject:uuidInfo];
            }
            archiveInfo.uuidInfos = uuidInfos;
        }
    }
}

/**
 * 获取所有 dSYM 文件目录.
 */
- (NSMutableArray *)allDSYMFilePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *archivesPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Developer/Xcode/Archives/"];
    NSURL *bundleURL = [NSURL fileURLWithPath:archivesPath];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:bundleURL
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler:^BOOL(NSURL *url, NSError *error)
    {
        if (error) {
            NSLog(@"[Error] %@ (%@)", error, url);
            return NO;
        }

        return YES;
    }];

    NSMutableArray *mutableFileURLs = [NSMutableArray array];
    for (NSURL *fileURL in enumerator) {
        NSString *filename;
        [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];

        NSNumber *isDirectory;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

        if ([filename hasPrefix:@"_"] && [isDirectory boolValue]) {
            [enumerator skipDescendants];
            continue;
        }

        //TODO:过滤部分没必要遍历的目录

        if ([filename hasSuffix:@".xcarchive"] && [isDirectory boolValue]){
            [mutableFileURLs addObject:fileURL.relativePath];
            [enumerator skipDescendants];
        }
    }
    return mutableFileURLs;
}

- (NSString *)runCommand:(NSString *)commandToRun
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    
    NSArray *arguments = @[@"-c",
            [NSString stringWithFormat:@"%@", commandToRun]];
//    NSLog(@"run command:%@", commandToRun);
    [task setArguments:arguments];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return output;
}


/**
 * 导出 ipa 文件
   xcodebuild -exportArchive -exportFormat ipa -archivePath "/path/to/archiveFile" -exportPath "/path/to/ipaFile"
 */
- (IBAction)exportIPA:(id)sender {
    if(!_selectedArchiveInfo){
        NSLog(@"还未选中 archive 文件");
        return;
    }
    
    NSString *ipaFileName = [_selectedArchiveInfo.archiveFileName stringByReplacingOccurrencesOfString:@"xcarchive" withString:@"ipa"];
    
    NSSavePanel *saveDlg = [[NSSavePanel alloc]init];
    saveDlg.title = ipaFileName;
    saveDlg.message = @"Save My File";
    saveDlg.allowedFileTypes = @[@"ipa"];
    saveDlg.nameFieldStringValue = ipaFileName;
    [saveDlg beginWithCompletionHandler: ^(NSInteger result){
        if(result == NSFileHandlingPanelOKButton){
            NSURL  *url =[saveDlg URL];
            NSLog(@"filePath url%@",url);
            NSString *exportCmd = [NSString stringWithFormat:@"/usr/bin/xcodebuild -exportArchive -exportFormat ipa -archivePath \"%@\" -exportPath \"%@\"", _selectedArchiveInfo.archiveFilePath, url.relativePath];
            [self runCommand:exportCmd];
        }
    }];
}


- (IBAction)aboutMe:(id)sender {
    self.aboutWindowController = [[AboutWindowController alloc] initWithWindowNibName:@"AboutWindowController"];
    [self.window beginSheet:self.aboutWindowController.window completionHandler:^(NSModalResponse returnCode) {
        switch (returnCode) {
            case NSModalResponseOK:
                NSLog(@"Done button tapped in Custom Sheet");
                break;
            case NSModalResponseCancel:
                NSLog(@"Cancel button tapped in Custom Sheet");
                break;
                
            default:
                break;
        }
        self.aboutWindowController = nil;
    }];
}

#pragma mark - NSTableViewDataSources
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView{
    return [_archiveFilesInfo count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row{
    ArchiveInfo *archiveInfo= _archiveFilesInfo[row];
    return archiveInfo.archiveFileName;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row{

    ArchiveInfo *archiveInfo= _archiveFilesInfo[row];
    NSString *identifier = tableColumn.identifier;
    NSView *view = [tableView makeViewWithIdentifier:identifier owner:self];
    NSArray *subviews = view.subviews;
    if (subviews.count > 0) {
        if ([identifier isEqualToString:@"name"]) {
            NSTextField *textField = subviews[0];
            textField.stringValue = archiveInfo.archiveFileName;
        }
    }
    return view;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification{
    NSInteger row = [notification.object selectedRow];
    _selectedArchiveInfo= _archiveFilesInfo[row];
    [self resetPreInformation];

    CGFloat radioButtonWidth = CGRectGetWidth(self.radioBox.contentView.frame);
    CGFloat radioButtonHeight = 18;
    [_selectedArchiveInfo.uuidInfos enumerateObjectsUsingBlock:^(UUIDInfo *uuidInfo, NSUInteger idx, BOOL *stop) {
        CGFloat space = (CGRectGetHeight(self.radioBox.contentView.frame) - _selectedArchiveInfo.uuidInfos.count * radioButtonHeight) / (_selectedArchiveInfo.uuidInfos.count + 1);
        CGFloat y = space * (idx + 1) + idx * radioButtonHeight;
        NSButton *radioButton = [[NSButton alloc] initWithFrame:NSMakeRect(10,y,radioButtonWidth,radioButtonHeight)];
        [radioButton setButtonType:NSRadioButton];
        [radioButton setTitle:uuidInfo.arch];
        radioButton.tag = idx + 1;
        [radioButton setAction:@selector(radioButtonAction:)];
        [self.radioBox.contentView addSubview:radioButton];
    }];
}

/**
 * 重置之前显示的信息
 */
- (void)resetPreInformation {
    [self.radioBox.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    _selectedUUIDInfo = nil;
    self.selectedUUIDLabel.stringValue = @"";
    self.defaultSlideAddressLabel.stringValue = @"";
    [self.errorMemoryAddressView setString:@""];
    [self.errorMessageView setString:@""];
}

- (void)radioButtonAction:(id)sender{
    NSButton *radioButton = sender;
    NSInteger tag = radioButton.tag;
    _selectedUUIDInfo = _selectedArchiveInfo.uuidInfos[tag - 1];
    _selectedUUIDLabel.stringValue = _selectedUUIDInfo.uuid;
    _defaultSlideAddressLabel.stringValue = _selectedUUIDInfo.defaultSlideAddress;
}

- (void)doubleActionMethod{
    NSLog(@"double action");
}

- (NSString *) analyzeAddress:(NSString *)addr {
    NSString *commandString = [NSString stringWithFormat:@"xcrun atos -arch %@ -o \"%@\" -l %@ %@", self.selectedUUIDInfo.arch, self.selectedUUIDInfo.executableFilePath, self.defaultSlideAddressLabel.stringValue, addr];
    return [self runCommand:commandString];
}

- (NSString *) analyzeLine:(NSString *)line {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(0x[0-9|a-f]+)"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!matches) {
        NSLog(@"* Can not analyze line:%@", line);
        return line;
    }
    
    NSTextCheckingResult *match = matches[0];
    NSString *addr = [line substringWithRange:match.range];
    NSString *analyzedAddr = [self analyzeAddress:addr];
    
    NSString *result = line;
    if (![addr isEqualToString:analyzedAddr]) {
        if (line.length > match.range.length) {
            // crash log
            result = [NSString stringWithFormat:@"%@ %@", [line substringToIndex:match.range.location + match.range.length], analyzedAddr];
        }
        else {
            // 单个的地址
            result = analyzedAddr;
        }
    }
    
    return result;
}

- (void) analyzeCrash:(NSString *)string complete:(void (^)(NSString *lineOutput))complete {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    
    dispatch_async(queue, ^{
        NSArray *lines = [string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *outputLines = [NSMutableArray arrayWithArray:lines];
        
        dispatch_group_t group = dispatch_group_create();
        
        [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger idx, BOOL * _Nonnull stop) {
            
            dispatch_group_async(group, queue, ^{
                NSString *lineOutput = [self analyzeLine:line];
                [outputLines replaceObjectAtIndex:idx withObject:lineOutput];
            });
        }];
        
        dispatch_group_notify(group, queue, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *string = [outputLines componentsJoinedByString:@""];
                
                if (complete) {
                    complete(string);
                }
            });
        });
    });
}

- (IBAction)analyse:(id)sender {
    if(self.selectedArchiveInfo == nil){
        return;
    }

    if(self.selectedUUIDInfo == nil){
        return;
    }

    if([self.defaultSlideAddressLabel.stringValue isEqualToString:@""]){
        return;
    }

    if([self.errorMemoryAddressView.string isEqualToString:@""]){
        return;
    }
    
    self.errorMessageView.string = @"";
    self.timeCostLabel.stringValue = @"";
    [self.progressIndicator startAnimation:nil];
    
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    
    __weak typeof(self) weakSelf = self;
    [self analyzeCrash:self.errorMemoryAddressView.string complete:^(NSString *output) {
        weakSelf.errorMessageView.string = output;
        
        weakSelf.timeCostLabel.stringValue = [NSString stringWithFormat:@"%@ms", @((long)((CFAbsoluteTimeGetCurrent() - startTime) * 1000))];
        [weakSelf.progressIndicator stopAnimation:nil];
    }];
}


- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender{

    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;

    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];

    if ( [[pboard types] containsObject:NSColorPboardType] ) {
        if (sourceDragMask & NSDragOperationGeneric) {
            return NSDragOperationGeneric;
        }
    }
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        if (sourceDragMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender{

}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];

    if ([[pboard types] containsObject:NSURLPboardType] ) {
        NSURL *fileURL = [NSURL URLFromPasteboard:pboard];
        NSLog(@"%@",fileURL);
    }

    if([[pboard types] containsObject:NSFilenamesPboardType]){
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        NSMutableArray *archiveFilePaths = [NSMutableArray arrayWithCapacity:1];
        for(NSString *filePath in files){
            if([filePath.pathExtension isEqualToString:@"xcarchive"]){
                NSLog(@"%@", filePath);
                [archiveFilePaths addObject:filePath];
            }
        }
        
        if(archiveFilePaths.count == 0){
            NSLog(@"没有包含任何 xcarchive 文件");
            return NO;
        }

        [self handleArchiveFileWithPath:archiveFilePaths];

        
    }

    return YES;
}

@end
