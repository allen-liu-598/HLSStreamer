//
//  M3u8Collector.swift
//  HLSStreamerContentUploadExtension
//
//
//  Created by @jdkula <jonathan@jdkula.dev> on 11/1/22.
//

import Foundation
import AVKit

/**
 * Provides the ongoing generation of a single M3U8 playlist,
 * accepting Segments to record details of.
 *
 * Once a segment is given to ``M3u8Collector``, it owns that segment,
 * and will delete it when it is no longer needed. The segments are assumed to
 * exist already by the time they get here.
 */
class M3u8Collector {
    private var headerSegment_: Segment? = nil
    private var segments_: [Segment] = []
    private var segmentDuration_: Double = 0.0
    
    private var seqNo_: Int = 1;
    private var segmentsToKeep_: Int = 0
    
    private let folderPrefix_: String
    
    init(folderPrefix: String) {
        folderPrefix_ = folderPrefix;
    }
    
    private func getHeader_() -> String {
        return "#EXTM3U\n"
        + "#EXT-X-TARGETDURATION:\(segmentDuration_)\n"
        + "#EXT-X-VERSION:7\n"
        + "#EXT-X-MEDIA-SEQUENCE:\(seqNo_)\n"
        + "#EXT-X-MAP:URI=\"\(folderPrefix_)/header.mp4\"\n"
    }
    
    private func getContent_() -> String {
        var lastSegment: Segment?
        
        var m3u8 = ""
        
        for segment in segments_ {
            if let previousSegmentInfo = lastSegment {
                let segmentDuration = segment.timingReport!.earliestPresentationTimeStamp.seconds - previousSegmentInfo.timingReport!.earliestPresentationTimeStamp.seconds
                
                // Sometimes we can get wildly negative segment durations; if this happens, we'll just skip the affected segment.
                if segmentDuration > 0 {
                    m3u8 += "#EXTINF:\(String(format: "%1.5f", segmentDuration)),\t\n\(folderPrefix_)/\(segment.index).m4s\n"
                }
            }
            lastSegment = segment
        }
        
        return m3u8
    }
    
    private func maybePruneSegments_() {
        while segments_.count > segmentsToKeep_ {
            let seg = segments_.remove(at: 0)
            seqNo_ += 1;
            
            // Asynchronously delete this segment.
            DispatchQueue.global(qos: .background).async {
                do {
                    try FileManager.default.removeItem(at: seg.url)
                } catch {
                    print("Got error removing item at", seg.url)
                }
            }
        }
    }
    
    /// Initializes a new M3u8 playlist with the given fMP4 configuration and header segment.
    func initM3u8(config: UserHLSConfiguration, segment: Segment) {
        assert(segment.isInitializationSegment)
        
        // 60 seconds worth of segments, or a minimum of 10. This is pretty arbitrary, could be configurable later.
        segmentsToKeep_ = max(10, Int(60 / config.segmentDuration))
        seqNo_ = 1;
        segments_ = [];
        headerSegment_ = segment;
        segmentDuration_ = config.segmentDuration
    }
    
    /// Adds a segment to the end of this playlist, pruning if necessary
    func addSegment(segment: Segment) {
        segments_.append(segment);
        maybePruneSegments_();
    }
    
    /// Generates and returns the current M3U8 playlist as a string.
    func getM3u8() -> String {
        return getHeader_() + getContent_()
    }
}
