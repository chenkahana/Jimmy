#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.chenkahana.Jimmy";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "DarkBackground" asset catalog color resource.
static NSString * const ACColorNameDarkBackground AC_SWIFT_PRIVATE = @"DarkBackground";

/// The "SurfaceElevated" asset catalog color resource.
static NSString * const ACColorNameSurfaceElevated AC_SWIFT_PRIVATE = @"SurfaceElevated";

/// The "SurfaceHighlighted" asset catalog color resource.
static NSString * const ACColorNameSurfaceHighlighted AC_SWIFT_PRIVATE = @"SurfaceHighlighted";

#undef AC_SWIFT_PRIVATE
