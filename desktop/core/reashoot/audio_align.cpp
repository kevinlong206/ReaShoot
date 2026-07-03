#include "reashoot/audio_align.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace reashoot {

std::vector<double> normalizedEnvelope(std::vector<double> envelope) {
  if (envelope.empty()) {
    return {};
  }
  double mean = 0.0;
  for (double value : envelope) {
    mean += value;
  }
  mean /= static_cast<double>(envelope.size());

  double energy = 0.0;
  for (double &value : envelope) {
    value -= mean;
    energy += value * value;
  }
  if (energy <= 1e-9) {
    return {};
  }
  return envelope;
}

namespace {

// Shared centered box-smoother with the given radius, using a sliding window.
std::vector<double> boxSmooth(const std::vector<double> &input, int radius) {
  std::vector<double> smoothed(input.size(), 0.0);
  double sum = 0.0;
  int count = 0;
  int left = 0;
  int right = -1;
  const int size = static_cast<int>(input.size());
  for (int i = 0; i < size; ++i) {
    const int targetRight = (std::min)(size - 1, i + radius);
    while (right < targetRight) {
      ++right;
      sum += input[static_cast<std::size_t>(right)];
      ++count;
    }
    const int targetLeft = (std::max)(0, i - radius);
    while (left < targetLeft) {
      sum -= input[static_cast<std::size_t>(left)];
      --count;
      ++left;
    }
    smoothed[static_cast<std::size_t>(i)] = count > 0 ? sum / static_cast<double>(count) : 0.0;
  }
  return smoothed;
}

} // namespace

std::vector<double> shapeEnvelope(std::vector<double> envelope, double peakRate) {
  if (envelope.empty()) {
    return {};
  }

  for (double &value : envelope) {
    value = std::log1p((std::max)(0.0, value) * 24.0);
  }

  const int radius = (std::max)(
      1, static_cast<int>(std::llround((peakRate >= align_constants::kFinePeakRate ? 0.015 : 0.25) * peakRate)));
  return normalizedEnvelope(boxSmooth(envelope, radius));
}

std::vector<double> normalizedSampleShape(std::vector<double> samples) {
  if (samples.empty()) {
    return {};
  }

  for (double &sample : samples) {
    sample = std::sqrt(std::fabs(sample));
  }

  const int radius = (std::max)(1, static_cast<int>(std::llround(0.0015 * align_constants::kSampleRate)));
  return normalizedEnvelope(boxSmooth(samples, radius));
}

double normalizedCorrelationAtLag(const std::vector<double> &video,
                                  const std::vector<double> &reference,
                                  int lagSamples,
                                  int minimumOverlapSamples) {
  int videoStart = 0;
  int referenceStart = lagSamples;
  int count = static_cast<int>(video.size());
  if (referenceStart < 0) {
    videoStart = -referenceStart;
    referenceStart = 0;
    count -= videoStart;
  }
  count = (std::min)(count, static_cast<int>(reference.size()) - referenceStart);
  if (count < minimumOverlapSamples) {
    return -std::numeric_limits<double>::infinity();
  }

  double dot = 0.0;
  double videoEnergy = 0.0;
  double referenceEnergy = 0.0;
  for (int i = 0; i < count; ++i) {
    const double videoValue = video[static_cast<std::size_t>(videoStart + i)];
    const double referenceValue = reference[static_cast<std::size_t>(referenceStart + i)];
    dot += videoValue * referenceValue;
    videoEnergy += videoValue * videoValue;
    referenceEnergy += referenceValue * referenceValue;
  }
  if (videoEnergy <= 1e-9 || referenceEnergy <= 1e-9) {
    return -std::numeric_limits<double>::infinity();
  }
  return dot / std::sqrt(videoEnergy * referenceEnergy);
}

LagMatch findBestLag(const std::vector<double> &video,
                     const std::vector<double> &reference,
                     int minLag,
                     int maxLag,
                     int minimumOverlapSamples) {
  LagMatch result;
  if (minLag > maxLag) {
    return result;
  }

  double bestScore = -std::numeric_limits<double>::infinity();
  int bestLag = minLag;
  for (int lag = minLag; lag <= maxLag; ++lag) {
    const double score = normalizedCorrelationAtLag(video, reference, lag, minimumOverlapSamples);
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  if (!std::isfinite(bestScore)) {
    return result;
  }

  result.lag = bestLag;
  result.score = bestScore;
  result.valid = true;
  return result;
}

} // namespace reashoot
