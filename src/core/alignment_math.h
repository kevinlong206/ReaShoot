#pragma once

#include <vector>

namespace reashoot::core {

struct TransientPeak {
  int index = 0;
  double value = 0.0;
};

std::vector<double> normalizedEnvelope(std::vector<double> envelope);
std::vector<double> shapeEnvelope(std::vector<double> envelope, double peakRate, double finePeakRate);
std::vector<double> transientEnvelope(const std::vector<double> &rawEnvelope);
double normalizedCorrelationAtLag(const std::vector<double> &video,
                                  const std::vector<double> &reference,
                                  int lagSamples,
                                  int minimumOverlapSamples);
std::vector<double> normalizedSampleShape(std::vector<double> samples, int sampleRate);
std::vector<TransientPeak> strongestTransientPeaks(const std::vector<double> &signal, double peakRate);

} // namespace reashoot::core
