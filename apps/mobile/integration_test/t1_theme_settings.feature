Feature: Choose the app theme

  Scenario: Switch from the default dark theme to light
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I select the light theme
    Then the app is shown in light theme

  Scenario: Switch to dark theme
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I select the dark theme
    Then the app is shown in dark theme
