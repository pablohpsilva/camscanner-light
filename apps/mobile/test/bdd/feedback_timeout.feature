Feature: Feedback submission survives a stalled network

  Scenario: A stalled submit surfaces the offline message and re-enables submit
    Given the feedback screen backed by a stalled service
    When I enter a feedback message
    And I tap send feedback
    Then I see the message check your connection and try again
    And the feedback submit control is enabled again
