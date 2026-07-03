#include "reashoot/audio_align.h"

#include <cassert>
#include <cmath>
#include <cstddef>
#include <iostream>
#include <random>
#include <vector>

namespace {

// Builds a noise-like reference signal and a copy delayed by knownLag samples.
// Cross-correlation of the shaped signals must recover knownLag.
void testRecoversKnownLag() {
  const int total = 4000;
  const int knownLag = 137;

  std::mt19937 rng(12345);
  std::uniform_real_distribution<double> dist(-1.0, 1.0);

  std::vector<double> base(total, 0.0);
  for (int i = 0; i < total; ++i) {
    base[static_cast<std::size_t>(i)] = dist(rng);
  }

  // reference[i] = base[i]; video[i] = base[i + knownLag] (video leads reference
  // by knownLag, so the reference matches the video at lag = knownLag).
  const int windowLength = total - knownLag - 1;
  std::vector<double> video(static_cast<std::size_t>(windowLength));
  std::vector<double> reference = base;
  for (int i = 0; i < windowLength; ++i) {
    video[static_cast<std::size_t>(i)] = base[static_cast<std::size_t>(i + knownLag)];
  }

  const std::vector<double> shapedVideo = reashoot::normalizedSampleShape(video);
  const std::vector<double> shapedReference = reashoot::normalizedSampleShape(reference);
  assert(!shapedVideo.empty());
  assert(!shapedReference.empty());

  const reashoot::LagMatch match =
      reashoot::findBestLag(shapedVideo, shapedReference, 0, 300, 500);

  assert(match.valid);
  // Smoothing can nudge the peak by a couple of samples; allow a small tolerance.
  assert(std::abs(match.lag - knownLag) <= 3);
  assert(match.score > 0.5);
}

void testEmptyRangeIsInvalid() {
  std::vector<double> a(100, 1.0);
  std::vector<double> b(100, 1.0);
  const reashoot::LagMatch match = reashoot::findBestLag(a, b, 10, 5, 10);
  assert(!match.valid);
}

void testNormalizedEnvelopeDropsFlatSignal() {
  std::vector<double> flat(100, 3.0);
  const std::vector<double> result = reashoot::normalizedEnvelope(std::move(flat));
  assert(result.empty()); // zero residual energy after mean removal
}

void testCorrelationSelfMatchIsOne() {
  std::vector<double> signal(200, 0.0);
  for (std::size_t i = 0; i < signal.size(); ++i) {
    signal[i] = std::sin(static_cast<double>(i) * 0.3);
  }
  const std::vector<double> prepared = reashoot::normalizedEnvelope(signal);
  assert(!prepared.empty());
  const double score = reashoot::normalizedCorrelationAtLag(prepared, prepared, 0, 10);
  assert(std::abs(score - 1.0) < 1e-9);
}

void testMinimumOverlapEnforced() {
  std::vector<double> video(100, 1.0);
  std::vector<double> reference(100, 1.0);
  // A lag that leaves only a tiny overlap must be rejected by the overlap floor.
  const double score = reashoot::normalizedCorrelationAtLag(video, reference, 95, 50);
  assert(!std::isfinite(score));
}

} // namespace

int main() {
  testRecoversKnownLag();
  testEmptyRangeIsInvalid();
  testNormalizedEnvelopeDropsFlatSignal();
  testCorrelationSelfMatchIsOne();
  testMinimumOverlapEnforced();
  std::cout << "audio_align_tests passed\n";
  return 0;
}
