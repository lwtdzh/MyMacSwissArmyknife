#import <Cocoa/Cocoa.h>
#import <FinderSync/FinderSync.h>

@protocol FinderSyncMenuControlling <NSObject>
- (nullable NSMenu *)menuForMenuKind:(FIMenuKind)menuKind;
- (void)openWithCommand:(nullable id)sender;
- (void)createFileCommand:(nullable id)sender;
- (void)openTerminalCommand:(nullable id)sender;
@end

@interface FinderSync : FIFinderSync
@end

@implementation FinderSync {
    id<FinderSyncMenuControlling> _menuController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        Class controllerClass = NSClassFromString(@"FinderSyncMenuController");
        _menuController = [[controllerClass alloc] init];

        NSMutableSet<NSURL *> *directoryURLs = [NSMutableSet setWithArray:
            [NSFileManager.defaultManager
                mountedVolumeURLsIncludingResourceValuesForKeys:nil
                options:0]
        ];
        [directoryURLs addObject:
            [NSURL fileURLWithPath:@"/System/Volumes/Data" isDirectory:YES]];
        FIFinderSyncController.defaultController.directoryURLs = directoryURLs;
    }
    return self;
}

- (void)configureMenu:(NSMenu *)menu {
    menu.autoenablesItems = NO;
    for (NSMenuItem *item in menu.itemArray) {
        item.enabled = YES;
        if (item.submenu != nil) {
            [self configureMenu:item.submenu];
        } else if (item.action != nil) {
            item.target = self;
        }
    }
}

- (NSMenu *)menuForMenuKind:(FIMenuKind)menuKind {
    NSMenu *menu = [_menuController menuForMenuKind:menuKind];
    [self configureMenu:menu];
    return menu;
}

- (void)openWithCommand:(id)sender {
    [_menuController openWithCommand:sender];
}

- (void)createFileCommand:(id)sender {
    [_menuController createFileCommand:sender];
}

- (void)openTerminalCommand:(id)sender {
    [_menuController openTerminalCommand:sender];
}

@end
