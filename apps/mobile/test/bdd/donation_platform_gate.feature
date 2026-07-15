Feature: Donation entry points respect the platform

  App Store guideline 3.1.1: no non-IAP donations on iOS, so every donation
  entry point is hidden there. Android keeps them.

  Scenario: Donation entry points are hidden on iOS
    Given the platform is iOS
    And the home screen is shown
    Then I do not see the donation banner
    When I open settings from home
    Then I do not see the support row
    And the platform override is cleared

  Scenario: Donation entry points are shown on Android
    Given the platform is Android
    And the home screen is shown
    Then I see the donation banner
    When I open settings from home
    Then I see the support row
    And the platform override is cleared
