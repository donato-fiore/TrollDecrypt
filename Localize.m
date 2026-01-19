#import "Localize.h"
#import <Foundation/Foundation.h>

@implementation Localize

+ (NSBundle *)mainBundle {
    return [NSBundle mainBundle];
}

+ (NSString *)_preferredLocalizationName {
    NSArray<NSString *> *availableLocaleNames = [[Localize mainBundle] localizations];
    NSArray<NSString *> *preferredLanguages = [NSLocale preferredLanguages];

    NSArray<NSString *> *preferredLocalizations = [NSBundle preferredLocalizationsFromArray:availableLocaleNames forPreferences:preferredLanguages];

    return [preferredLocalizations firstObject] ?: @"en";
}

+ (NSString *)_preferredLocalizationPath { 
    NSString *const basePath = [NSString stringWithFormat:@"%@/LANG.lproj/Localizable.strings", [[Localize mainBundle] resourcePath]];
    NSString *preferredPath = [basePath stringByReplacingOccurrencesOfString:@"LANG" withString:[Localize _preferredLocalizationName]];

    if (![[NSFileManager defaultManager] fileExistsAtPath:preferredPath]) {
        preferredPath = [basePath stringByReplacingOccurrencesOfString:@"LANG" withString:@"en"];
    }

    return preferredPath;
}

+ (NSDictionary *)_localizedStringsDictionary {
    static NSDictionary *localizedStringsDictionary = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        localizedStringsDictionary = [NSDictionary dictionaryWithContentsOfFile:[Localize _preferredLocalizationPath]];
    });

    return localizedStringsDictionary;
}

+ (NSString *)localizedStringForKey:(NSString *)key {
    return [Localize localizedStringForKey:key fallback:key];
}

+ (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback {
    NSDictionary *localizedStringsDictionary = [Localize _localizedStringsDictionary];
    NSString *localizedString = [localizedStringsDictionary objectForKey:key];

    if (!localizedString) return fallback;
    return localizedString;
}

@end
