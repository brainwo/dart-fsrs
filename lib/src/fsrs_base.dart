import 'dart:core';
import 'dart:math';
import './models.dart';

class FSRS {
  late Parameters p;
  late double decay;
  late double factor;

  FSRS() {
    p = Parameters();
    decay = -0.5;
    factor = pow(0.9, 1 / decay) - 1;
  }

  Map<Rating, SchedulingInfo> repeat(Card card, DateTime now) {
    card = Card.copyFrom(card);
    if (card.state == State.New) {
      card.elapsedDays = 0;
    } else {
      card.elapsedDays = now.difference(card.lastReview).inDays;
    }
    card.lastReview = now;
    card.reps++;

    final s = SchedulingCards(card);
    s.updateState(card.state);

    if (card.state == State.New) {
      _initDS(s);

      s.again.due = now.add(Duration(minutes: 1));
      s.hard.due = now.add(Duration(minutes: 5));
      s.good.due = now.add(Duration(minutes: 10));
      final easyInterval = _nextInterval(s.easy.stability);
      s.easy.scheduledDays = easyInterval;
      s.easy.due = now.add(Duration(days: easyInterval));
    } else if (card.state == State.Learning || card.state == State.Relearning) {
      final hardInterval = 0;
      final goodInterval = _nextInterval(s.good.stability);
      final easyInterval =
          max(_nextInterval(s.easy.stability), goodInterval + 1);

      s.schedule(now, hardInterval.toDouble(), goodInterval.toDouble(),
          easyInterval.toDouble());
    } else if (card.state == State.Review) {
      final interval = card.elapsedDays;
      final lastD = card.difficulty;
      final lastS = card.stability;
      final retrievability = _forgettingCurve(interval, lastS);
      _nextDS(s, lastD, lastS, retrievability);

      var hardInterval = _nextInterval(s.hard.stability);
      var goodInterval = _nextInterval(s.good.stability);
      hardInterval = min(hardInterval, goodInterval);
      goodInterval = max(goodInterval, hardInterval + 1);
      final easyInterval =
          max(_nextInterval(s.easy.stability), goodInterval + 1);
      s.schedule(now, hardInterval.toDouble(), goodInterval.toDouble(),
          easyInterval.toDouble());
    }
    return s.recordLog(card, now);
  }

  void _initDS(SchedulingCards s) {
    s.again.difficulty = _initDifficulty(Rating.Again.val);
    s.again.stability = _initStability(Rating.Again.val);
    s.hard.difficulty = _initDifficulty(Rating.Hard.val);
    s.hard.stability = _initStability(Rating.Hard.val);
    s.good.difficulty = _initDifficulty(Rating.Good.val);
    s.good.stability = _initStability(Rating.Good.val);
    s.easy.difficulty = _initDifficulty(Rating.Easy.val);
    s.easy.stability = _initStability(Rating.Easy.val);
  }

  double _initStability(int r) {
    return max(p.w[r - 1], 0.1);
  }

  double _initDifficulty(int r) {
    return min(max(p.w[4] - p.w[5] * (r - 3), 1), 10);
  }

  double _forgettingCurve(int elapsedDays, double stability) {
    return pow(1 + factor * elapsedDays / stability, decay).toDouble();
  }

  int _nextInterval(double s) {
    final newInterval = s / factor * (pow(p.requestRetention, 1 / decay) - 1);
    return min(max(newInterval.round(), 1), p.maximumInterval);
  }

  double _nextDifficulty(double d, int r) {
    final nextD = d - p.w[6] * (r - 3);
    return min(max(_meanReversion(p.w[4], nextD), 1), 10);
  }

  double _meanReversion(double init, double current) {
    return p.w[7] * init + (1 - p.w[7]) * current;
  }

  double _nextRecallStability(double d, double s, double r, Rating rating) {
    final hardPenalty = (rating == Rating.Hard) ? p.w[15] : 1;
    final easyBonus = (rating == Rating.Easy) ? p.w[16] : 1;
    return s *
        (1 +
            exp(p.w[8]) *
                (11 - d) *
                pow(s, -p.w[9]) *
                (exp((1 - r) * p.w[10]) - 1) *
                hardPenalty *
                easyBonus);
  }

  double _nextForgetStability(double d, double s, double r) {
    return p.w[11] *
        pow(d, -p.w[12]) *
        (pow(s + 1, p.w[13]) - 1) *
        exp((1 - r) * p.w[14]);
  }

  void _nextDS(
      SchedulingCards s, double lastD, double lastS, double retrievability) {
    s.again.difficulty = _nextDifficulty(lastD, Rating.Again.val);
    s.again.stability = _nextForgetStability(lastD, lastS, retrievability);
    s.hard.difficulty = _nextDifficulty(lastD, Rating.Hard.val);
    s.hard.stability =
        _nextRecallStability(lastD, lastS, retrievability, Rating.Hard);
    s.good.difficulty = _nextDifficulty(lastD, Rating.Good.val);
    s.good.stability =
        _nextRecallStability(lastD, lastS, retrievability, Rating.Good);
    s.easy.difficulty = _nextDifficulty(lastD, Rating.Easy.val);
    s.easy.stability =
        _nextRecallStability(lastD, lastS, retrievability, Rating.Easy);
  }
}
