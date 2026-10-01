import 'analytics.dart';

/// Moments that justify reaching out to the user.
///
/// Each one is tied to a real change in their practice state — there is no
/// generic "come back!" trigger, because a notification with nothing behind it
/// is how an app gets muted.
enum RetentionMoment {
  sessionCompleted,
  skillDetected,
  scenarioCleared,
  playbookSaved,
  practiceRecommended,
  userInactive,
  streakMilestone,
}

/// A notification VERBAL would send, with the copy derived from user state.
class RetentionNotification {
  const RetentionNotification({
    required this.moment,
    required this.title,
    required this.body,
    required this.deepLink,
  });

  final RetentionMoment moment;
  final String title;
  final String body;

  /// Route the app should open. Matches the router's paths.
  final String deepLink;
}

/// Builds the copy for each moment.
///
/// Kept as pure functions so the messages can be reviewed and tested without a
/// push provider attached. No provider (OneSignal or otherwise) is wired into
/// this build — [NotificationScheduler] is the seam where one would go.
class RetentionCopy {
  const RetentionCopy._();

  static RetentionNotification forSkillGap({
    required String skillLabel,
    required String scenarioTitle,
    required String scenarioId,
  }) =>
      RetentionNotification(
        moment: RetentionMoment.practiceRecommended,
        title: 'Your next practice',
        body: 'Focus on $skillLabel. $scenarioTitle is built to stress it.',
        deepLink: '/scenarios/$scenarioId',
      );

  static RetentionNotification forImprovement({
    required String skillLabel,
    required int delta,
  }) =>
      RetentionNotification(
        moment: RetentionMoment.skillDetected,
        title: '$skillLabel is improving',
        body: 'Up $delta since your last few sessions. Ready for a harder one?',
        deepLink: '/scenarios',
      );

  static RetentionNotification forInactivity({required int days}) =>
      RetentionNotification(
        moment: RetentionMoment.userInactive,
        title: 'Still avoiding that conversation?',
        body: 'It has been $days days. One rehearsal is about ten minutes.',
        deepLink: '/',
      );
}

/// Where a push provider would be attached.
///
/// The interface exists so the app can record retention moments today and route
/// them to a provider later without touching call sites.
abstract class NotificationScheduler {
  Future<void> schedule(RetentionNotification notification);
}

/// Records moments to analytics only. This is what actually runs in this build.
class LocalOnlyScheduler implements NotificationScheduler {
  const LocalOnlyScheduler(this._analytics);

  final Analytics _analytics;

  @override
  Future<void> schedule(RetentionNotification n) async {
    _analytics.track(AnalyticsEvent.notificationOpened, {
      'moment': n.moment.name,
      'scheduled': false,
    });
  }
}
