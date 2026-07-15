Feature: Donate to support the app

  Scenario: The home banner opens the donation screen on platforms with donations
    Given the app is launched with camera permission granted and empty storage
    Then the donation banner matches this platform's donation availability
    And tapping the donation banner opens the donation disclaimer where available
