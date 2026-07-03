#include "alignment_math.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace reashoot::core {

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

std::vector<double> shapeEnvelope(std::vector<double> envelope, double peakRate, double finePeakRate) {
  if (envelope.empty()) {
    return {};
  }

  for (double &value : envelope) {
    value = std::log1p((std::max)(0.0, value) * 24.0);
  }

  const int radius = (std::max)(1, static_cast<int>(std::llround((peakRate >= finePeakRate ? 0.015 : 0.25) * peakRate)));
  std::vector<double> smoothed(envelope.size(), 0.0);
  double sum = 0.0;
  int count = 0;
  int left = 0;
  int right = -1;
  for (int i = 0; i < static_cast<int>(envelope.size()); ++i) {
    const int targetRight = (std::min)(static_cast<int>(envelope.size()) - 1, i + radius);
    while (right < targetRight) {
      ++right;
      sum += envelope[static_cast<size_t>(right)];
      ++count;
    }
    const int targetLeft = (std::max)(0, i - radius);
    while (left < targetLeft) {
      sum -= envelope[static_cast<size_t>(left)];
      --count;
      ++left;
    }
    smoothed[static_cast<size_t>(i)] = count > 0 ? sum / static_cast<double>(count) : 0.0;
  }

  return normalizedEnvelope(std::move(smoothed));
}

std::vector<double> transientEnvelope(const std::vector<double> &rawEnvelope) {
  if (rawEnvelope.empty()) {
    return {};
  }
  std::vector<double> onset(rawEnvelope.size(), 0.0);
  double slowEnvelope = rawEnvelope.front();
  for (size_t i = 1; i < rawEnvelope.size(); ++i) {
    const double previousSlow = slowEnvelope;
    slowEnvelope = (0.90 * slowEnvelope) + (0.10 * rawEnvelope[i]);
    onset[i] = (std::max)(0.0, rawEnvelope[i] - previousSlow);
  }
  return normalizedEnvelope(std::move(onset));
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
    const double videoValue = video[static_cast<size_t>(videoStart + i)];
    const double referenceValue = reference[static_cast<size_t>(referenceStart + i)];
    dot += videoValue * referenceValue;
    videoEnergy += videoValue * videoValue;
    referenceEnergy += referenceValue * referenceValue;
  }
  if (videoEnergy <= 1e-9 || referenceEnergy <= 1e-9) {
    return -std::numeric_limits<double>::infinity();
  }
  return dot / std::sqrt(videoEnergy * referenceEnergy);
}

std::vector<double> normalizedSampleShape(std::vector<double> samples, int sampleRate) {
  if (samples.empty()) {
    return {};
  }

  for (double &sample : samples) {
    sample = std::sqrt(std::fabs(sample));
  }

  const int radius = (std::max)(1, static_cast<int>(std::llround(0.0015 * sampleRate)));
  std::vector<double> smoothed(samples.size(), 0.0);
  double sum = 0.0;
  int count = 0;
  int left = 0;
  int right = -1;
  for (int i = 0; i < static_cast<int>(samples.size()); ++i) {
    const int targetRight = (std::min)(static_cast<int>(samples.size()) - 1, i + radius);
    while (right < targetRight) {
      ++right;
      sum += samples[static_cast<size_t>(right)];
      ++count;
    }
    const int targetLeft = (std::max)(0, i - radius);
    while (left < targetLeft) {
      sum -= samples[static_cast<size_t>(left)];
      --count;
      ++left;
    }
    smoothed[static_cast<size_t>(i)] = count > 0 ? sum / static_cast<double>(count) : 0.0;
  }

  return normalizedEnvelope(std::move(smoothed));
}

std::vector<TransientPeak> strongestTransientPeaks(const std::vector<double> &signal, double peakRate) {
  std::vector<TransientPeak> peaks;
  if (signal.size() < 3) {
    return peaks;
  }

  double maxValue = 0.0;
  for (double value : signal) {
    maxValue = (std::max)(maxValue, value);
  }
  if (maxValue <= 0.0) {
    return peaks;
  }

  const double threshold = maxValue * 0.35;
  const int minDistance = static_cast<int>(std::llround(0.08 * peakRate));
  for (int i = 1; i < static_cast<int>(signal.size()) - 1; ++i) {
    const double value = signal[static_cast<size_t>(i)];
    if (value < threshold || value < signal[static_cast<size_t>(i - 1)] || value < signal[static_cast<size_t>(i + 1)]) {
      continue;
    }
    bool merged = false;
    for (TransientPeak &peak : peaks) {
      if (std::abs(peak.index - i) <= minDistance) {
        if (value > peak.value) {
          peak.index = i;
          peak.value = value;
        }
        merged = true;
        break;
      }
    }
    if (!merged) {
      peaks.push_back({i, value});
    }
  }

  std::sort(peaks.begin(), peaks.end(), [](const TransientPeak &a, const TransientPeak &b) {
    return a.value > b.value;
  });
  if (peaks.size() > 32) {
    peaks.resize(32);
  }
  return peaks;
}

} // namespace reashoot::core
