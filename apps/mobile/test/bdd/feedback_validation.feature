Feature: Feedback submission result messaging

  Scenario: Server rejects the feedback as invalid and the user goes back
    Given the feedback screen backed by a service that rejects as invalid
    When I enter a feedback message
    And I tap send feedback
    Then I see the message please check your message and try again
    When I tap the feedback back button
    Then the feedback screen is dismissed
