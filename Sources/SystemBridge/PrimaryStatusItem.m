#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <float.h>
#import <math.h>
#import "SystemBridge.h"

// Public NSStatusItem mirrors its layout on every menu bar. Keep the compatibility
// surface local, check its ABI, and scope this app's compositor entries only.
@interface NSStatusItem (IToolsDisplayCompatibility)
- (void)_updateItemForMetrics:(NSDictionary *)metrics;
- (void)_updateItemForCurrentMetrics;
- (void)_updateReplicants;
@end
@interface NSObject (IToolsStatusRegistry)
- (NSString *)confiningDisplayID;
- (void)setConfiningDisplayID:(NSString *)identifier;
- (float)preferredPosition;
- (void)setPreferredPosition:(float)position;
- (BOOL)isInstalled;
- (void)setInstalled:(BOOL)installed;
@end
static id it_field(id object, const char *name) {
    Ivar field = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return field && ivar_getTypeEncoding(field)[0] == '@' ? object_getIvar(object, field) : nil;
}
static NSString *it_primary_identifier(void) {
    NSNumber *number = NSScreen.screens.firstObject.deviceDescription[@"NSScreenNumber"];
    CFUUIDRef uuid = number ? CGDisplayCreateUUIDFromDisplayID(number.unsignedIntValue) : NULL;
    if (!uuid) return nil;
    CFStringRef string = CFUUIDCreateString(NULL, uuid);
    NSString *result = [NSString stringWithString:(__bridge NSString *)string];
    CFRelease(string); CFRelease(uuid); return result;
}
@interface IToolsStatusDisplayState : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *autosaveName;
@property(nonatomic) float position;
@property(nonatomic) BOOL metricsValid;
@end
@implementation IToolsStatusDisplayState
#if !__has_feature(objc_arc)
- (void)dealloc { [_identifier release]; [_autosaveName release]; [super dealloc]; }
#endif
@end
static char it_scope_key;
static IMP it_original_metrics;
static IMP it_original_replicants;
static BOOL it_pin(NSStatusItem *item, NSString *identifier, BOOL relayout) {
    id root = it_field(item, "_cgsItem");
    id replicas = it_field(item, "_replicants");
    Class registry = NSClassFromString(@"NSCGSStatusItem");
    if (![root isKindOfClass:registry] || ![replicas isKindOfClass:NSArray.class]) return NO;
    IToolsStatusDisplayState *state = objc_getAssociatedObject(item, &it_scope_key);
    if (item.isVisible && NSEvent.pressedMouseButtons == 0) {
        if (item.autosaveName && ![state.autosaveName isEqualToString:item.autosaveName]) {
            id saved = [NSUserDefaults.standardUserDefaults objectForKey:[@"NSStatusItem Preferred Position " stringByAppendingString:item.autosaveName]];
            if ([saved isKindOfClass:NSNumber.class] && isfinite([saved floatValue]) && [saved floatValue] < FLT_MAX) [root setPreferredPosition:[saved floatValue]];
            state.autosaveName = item.autosaveName;
        }
        // AppKit uses FLT_MAX when a hidden confined item is reinstalled. Restore
        // the last ordinary position; normal Cmd-drag continues to update it.
        float position = [root preferredPosition];
        if (!isfinite(position) || position == FLT_MAX) [root setPreferredPosition:state.position];
        else state.position = position;
    }
    if (relayout) [root setConfiningDisplayID:nil];
    if (![[root confiningDisplayID] isEqualToString:identifier]) [root setConfiningDisplayID:identifier];
    // The original stays installed and participates in native primary layout;
    // uninstalling its replicas releases their slots as well as their click areas.
    for (id replica in replicas) {
        id entry = it_field(replica, "_cgsItem");
        if (![entry isKindOfClass:registry]) return NO;
        if ([entry isInstalled]) [entry setInstalled:NO];
    }
    return YES;
}
static void it_scoped_metrics(NSStatusItem *item, SEL command, NSDictionary *metrics) {
    void (*original)(id, SEL, NSDictionary *) = (void *)it_original_metrics;
    IToolsStatusDisplayState *state = objc_getAssociatedObject(item, &it_scope_key);
    if (!state) { original(item, command, metrics); return; }
    NSString *selected = state.identifier ?: it_primary_identifier();
    NSDictionary *target = nil;
    if ([metrics isKindOfClass:NSDictionary.class] && [metrics[@"displays"] isKindOfClass:NSArray.class])
        for (id display in metrics[@"displays"])
            if ([display isKindOfClass:NSDictionary.class] && [display[@"identifier"] isEqual:selected]) { target = display; break; }
    state.metricsValid = NO;
    BOOL valid = target && [target[@"bar_height"] isKindOfClass:NSNumber.class] &&
        [target[@"bar_height"] doubleValue] > 0 && [target[@"bar_height"] doubleValue] <= 64;
    if (valid) for (id display in metrics[@"displays"])
        if (![display isKindOfClass:NSDictionary.class]) { valid = NO; break; }
    if (!valid) { original(item, command, metrics); item.visible = NO; return; }
    state.metricsValid = YES;
    // Preserve the real active display and native styling/lifecycle. The selected
    // bar supplies the height of this item's original window before confinement.
    NSMutableDictionary *scoped = [metrics mutableCopy];
    NSMutableArray *displays = [NSMutableArray array];
    for (NSDictionary *display in metrics[@"displays"]) {
        NSMutableDictionary *entry = [display mutableCopy]; entry[@"bar_height"] = target[@"bar_height"];
        [displays addObject:entry];
#if !__has_feature(objc_arc)
        [entry release];
#endif
    }
    scoped[@"displays"] = displays;
    @try {
        original(item, command, scoped);
        state.metricsValid = it_pin(item, selected, YES);
        if (!state.metricsValid) item.visible = NO;
    } @catch (NSException *exception) { state.metricsValid = NO; item.visible = NO; }
#if !__has_feature(objc_arc)
    [scoped release];
#endif
}
static void it_scoped_replicants(NSStatusItem *item, SEL command) {
    ((void (*)(id, SEL))it_original_replicants)(item, command);
    IToolsStatusDisplayState *state = objc_getAssociatedObject(item, &it_scope_key);
    if (state.metricsValid) {
        @try { if (!it_pin(item, state.identifier ?: it_primary_identifier(), NO)) item.visible = NO; }
        @catch (NSException *exception) { state.metricsValid = NO; item.visible = NO; }
    }
}
static BOOL it_method_matches(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments.count + 2) return NO;
    char type[32]; method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, result) && !(strcmp(result, "B") == 0 && strcmp(type, "c") == 0)) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        const char *expected = arguments[i].UTF8String;
        if (strcmp(type, expected) && !(strcmp(expected, "B") == 0 && strcmp(type, "c") == 0)) return NO;
    }
    return YES;
}
int it_primary_status_item_supported(void) {
    Class registry = NSClassFromString(@"NSCGSStatusItem");
    Ivar root = class_getInstanceVariable(NSStatusItem.class, "_cgsItem");
    Ivar replicas = class_getInstanceVariable(NSStatusItem.class, "_replicants");
    return root && replicas && ivar_getTypeEncoding(root)[0] == '@' && ivar_getTypeEncoding(replicas)[0] == '@' &&
        it_method_matches(registry, @selector(confiningDisplayID), "@", @[]) &&
        it_method_matches(registry, @selector(setConfiningDisplayID:), "v", @[@"@"]) &&
        it_method_matches(registry, @selector(preferredPosition), "f", @[]) &&
        it_method_matches(registry, @selector(setPreferredPosition:), "v", @[@"f"]) &&
        it_method_matches(registry, @selector(isInstalled), "B", @[]) &&
        it_method_matches(registry, @selector(setInstalled:), "v", @[@"B"]) &&
        it_method_matches(NSStatusItem.class, @selector(_updateItemForMetrics:), "v", @[@"@"]) &&
        it_method_matches(NSStatusItem.class, @selector(_updateItemForCurrentMetrics), "v", @[]) &&
        it_method_matches(NSStatusItem.class, @selector(_updateReplicants), "v", @[]);
}
void *it_primary_status_item_create(double length) {
    if (!it_primary_status_item_supported()) return NULL;
    NSStatusItem *item = nil;
    @try {
        if (!it_original_metrics) {
            Method method = class_getInstanceMethod(NSStatusItem.class, @selector(_updateItemForMetrics:));
            it_original_metrics = method_setImplementation(method, (IMP)it_scoped_metrics);
            Method replicants = class_getInstanceMethod(NSStatusItem.class, @selector(_updateReplicants));
            it_original_replicants = method_setImplementation(replicants, (IMP)it_scoped_replicants);
        }
        // Use the public factory intact, including AppKit's native registration,
        // autosave and KVO. The compatibility callback changes only associated items;
        // other status items in this process use the original implementation.
        item = [NSStatusBar.systemStatusBar statusItemWithLength:length];
        IToolsStatusDisplayState *state = [[IToolsStatusDisplayState alloc] init];
        state.identifier = it_primary_identifier(); state.position = -1;
        objc_setAssociatedObject(item, &it_scope_key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if !__has_feature(objc_arc)
        [state release];
#endif
        [item _updateItemForCurrentMetrics];
#if __has_feature(objc_arc)
        return (__bridge_retained void *)item;
#else
        return (void *)[item retain];
#endif
    } @catch (NSException *exception) {
        if (item) [NSStatusBar.systemStatusBar removeStatusItem:item];
        return NULL;
    }
}
int it_primary_status_item_is_confined(void *object) {
    return object && objc_getAssociatedObject((__bridge NSStatusItem *)object, &it_scope_key) != nil;
}
int it_primary_status_item_pin(void *object, const char *display) {
    if (!it_primary_status_item_is_confined(object) || !display || !it_primary_status_item_supported()) return 0;
    NSStatusItem *item = (__bridge NSStatusItem *)object;
    IToolsStatusDisplayState *state = objc_getAssociatedObject(item, &it_scope_key);
    NSString *identifier = [NSString stringWithUTF8String:display]; if (!identifier) return 0;
    @try {
        if (!state.metricsValid || ![state.identifier isEqualToString:identifier]) {
            state.identifier = identifier; [item _updateItemForCurrentMetrics];
        }
        return state.metricsValid && it_pin(item, identifier, NO);
    } @catch (NSException *exception) { return 0; }
}
int it_primary_status_items_set_positions(void * const *objects, const double *positions, int count) {
    if (!objects || !positions || count < 1 || count > 8 || !it_primary_status_item_supported()) return 0;
    NSMutableArray<NSStatusItem *> *items = [NSMutableArray array];
    Class registry = NSClassFromString(@"NSCGSStatusItem");
    for (int i = 0; i < count; i++) {
        if (!it_primary_status_item_is_confined(objects[i]) || !isfinite(positions[i]) || positions[i] < 0 || positions[i] >= FLT_MAX) return 0;
        NSStatusItem *item = (__bridge NSStatusItem *)objects[i];
        if (![it_field(item, "_cgsItem") isKindOfClass:registry]) return 0;
        [items addObject:item];
    }
    @try {
        // Remove the whole group before changing insertion points. Reinstalling
        // one item at a time lets intermediate layouts move the remaining slots
        // while their cached display metrics still describe another screen.
        for (NSStatusItem *item in items) item.visible = NO;
        for (int i = 0; i < count; i++) {
            NSStatusItem *item = items[i];
            id root = it_field(item, "_cgsItem");
            if (![root isKindOfClass:registry]) @throw [NSException exceptionWithName:@"IToolsStatusLayout" reason:@"Native status entry unavailable" userInfo:nil];
            IToolsStatusDisplayState *state = objc_getAssociatedObject(item, &it_scope_key);
            float position = (float)positions[i];
            if (item.autosaveName) {
                [NSUserDefaults.standardUserDefaults setDouble:position forKey:[@"NSStatusItem Preferred Position " stringByAppendingString:item.autosaveName]];
                state.autosaveName = item.autosaveName;
            }
            state.position = position; [root setPreferredPosition:position];
        }
        for (NSStatusItem *item in items) item.visible = YES;
        for (NSStatusItem *item in items) [item _updateItemForCurrentMetrics];
        for (NSStatusItem *item in items) {
            IToolsStatusDisplayState *state = objc_getAssociatedObject(item, &it_scope_key);
            if (!state.metricsValid || !it_pin(item, state.identifier ?: it_primary_identifier(), NO)) return 0;
        }
        return 1;
    } @catch (NSException *exception) {
        for (NSStatusItem *item in items) { item.visible = YES; [item _updateItemForCurrentMetrics]; }
        return 0;
    }
}
int it_primary_status_item_set_position(void *object, double preferred) {
    return it_primary_status_items_set_positions(&object, &preferred, 1);
}

int it_primary_status_item_reset_position(void *object) {
    return it_primary_status_item_set_position(object, 0);
}
