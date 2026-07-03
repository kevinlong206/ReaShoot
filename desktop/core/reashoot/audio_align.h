#pragma once

#include <cstddef>
#include <vector>

namespace reashoot {

// Alignment tuning constants, mirroring the macOS plugin 1:1 so Windows produces
// identical alignment behaviour.
namespace align_constants {

inline constexpr double kPeakRate = 200.0;
inline constexpr double kFinePeakRate = 1000.0;
inline constexpr int kSampleRate = 48000;
inline constexpr double kMaxDuration = 120.0;
inline constexpr double kFineMaxDuration = 30.0;
inline constexpr double kFineSearchSeconds = 0.20;
inline constexpr double kSampleRefineDuration = 1.0;
inline constexpr double kSampleRefineSearchSeconds = 0.030;
inline constexpr double kSearchSeconds = 5.0;
inline constexpr double kMinimumScore = 0.15;
inline constexpr int kRetryLimit = 15;

} // namespace align_constants

// Result of a lag search: the best lag (in samples) and its normalized
// correlation score. valid is false when no lag met the minimum overlap.
struct LagMatch {
  int lag = 0;
  double score = 0.0;
  bool valid = false;
};

// Mean-removes the buffer and returns it, or an empty vector if the residual
// energy is negligible (matching normalizedEnvelope).
std::vector<double> normalizedEnvelope(std::vector<double> envelope);

// Compresses (log1p), box-smooths (radius scaled by peakRate), and normalizes an
// amplitude envelope, matching shapeEnvelope.
std::vector<double> shapeEnvelope(std::vector<double> envelope, double peakRate);

// Rectifies (sqrt|x|), box-smooths (~1.5 ms radius), and normalizes raw audio
// samples, matching normalizedSampleShape. Uses kSampleRate for the radius.
std::vector<double> normalizedSampleShape(std::vector<double> samples);

// Normalized cross-correlation of two prepared signals at a given lag, matching
// normalizedCorrelationAtLag. Returns -inf when the overlap is below
// minimumOverlapSamples or either window has negligible energy.
double normalizedCorrelationAtLag(const std::vector<double> &video,
                                  const std::vector<double> &reference,
                                  int lagSamples,
                                  int minimumOverlapSamples);

// Scans lags in [minLag, maxLag] and returns the best-scoring lag, mirroring the
// coarse/refine search loops. valid is false when the range is empty or no lag
// produced a finite score.
LagMatch findBestLag(const std::vector<double> &video,
                     const std::vector<double> &reference,
                     int minLag,
                     int maxLag,
                     int minimumOverlapSamples);

} // namespace reashoot
