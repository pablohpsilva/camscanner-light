Feature: FB1 Feedback submission on a real device

  The feedback screen measured 0% e2e coverage: its only tests live in the HOST
  suite (test/bdd/feedback_*.feature), which `flutter test --coverage` reports
  but the device sweep never runs. That matters beyond the coverage number —
  FeedbackScreen embeds a WebView (Turnstile), and a host test cannot render a
  platform view at all, so the screen had never been built on real hardware.

  These reuse the existing host steps verbatim; the service is injected and
  every HTTP client is a fake, so no network and no Worker deployment needed.

  Scenario: A stalled submit surfaces the offline message and re-enables submit
    Given the feedback screen backed by a stalled service
    When I enter a feedback message
    And I tap send feedback
    Then I see the message check your connection and try again
    And the feedback submit control is enabled again

  Scenario: Server rejects the feedback as invalid and the user goes back
    Given the feedback screen backed by a service that rejects as invalid
    When I enter a feedback message
    And I tap send feedback
    Then I see the message please check your message and try again
    When I tap the feedback back button
    Then the feedback screen is dismissed
