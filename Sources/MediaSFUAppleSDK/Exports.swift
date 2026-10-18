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
#endif
