Feature: Donate to support the app

  Scenario: Open the donation screen from the always-visible home banner
    Given the app is launched with camera permission granted and empty storage
    When I tap the donation banner
    Then I see the donation disclaimer
