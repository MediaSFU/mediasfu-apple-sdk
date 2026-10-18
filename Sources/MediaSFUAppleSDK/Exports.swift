@_exported import Foundation

#if canImport(MediaSFUSDK)
@_exported import MediaSFUSDK
#elseif canImport(shared)
@_exported import shared
#elseif os(iOS)
#error("MediaSFUAppleSDK requires the MediaSFUSDK runtime on iOS. Link its binary target before building the app.")
#endif

#if canImport(MediaSFUMediasoupClient)
@_exported import MediaSFUMediasoupClient
#elseif os(iOS) && MEDIA_SFU_HAS_TRANSLATION_VOICES
#error("Translation validation requires an importable MediaSFUMediasoupClient. Set MEDIA_SFU_MEDIASOUP_PACKAGE_PATH to the maintained source package when validating local runtimes.")
#endif
