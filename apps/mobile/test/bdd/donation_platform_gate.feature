Feature: Donation entry points respect the platform

  App Store guideline 3.1.1: donations to the developer must go through
  In-App Purchase on iOS/iPadOS. Both platforms show a donation entry point;
  the destination screen picks the compliant body per platform (Ko-fi/BTC on
  Android, the IAP tip jar on iOS).

  Scenario: Donation entry points are shown on iOS
    Given the platform is iOS
    And the home screen is shown
    Then I see the donation banner
    When I open settings from home
    Then I see the support row
    And the platform override is cleared

  Scenario: Home actions keep clear of the screen bottom on iOS
    Given the platform is iOS
    And the device has a bottom safe area inset
    And the home screen is shown
    Then the scan actions sit clear of the bottom inset
    And the platform override is cleared

  Scenario: Donation entry points are shown on Android
    Given the platform is Android
    And the home screen is shown
    Then I see the donation banner
    When I open settings from home
    Then I see the support row
    And the platform override is cleared
