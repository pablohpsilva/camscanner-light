Feature: App language

  The app follows the device language when supported, falls back to English
  otherwise, and lets the user pick a language (or System default) in
  Settings. The choice persists across launches.

  Scenario: A supported device language is used automatically
    Given the device language is Brazilian Portuguese
    And the app is launched with empty storage and mocked preferences
    Then the home title is shown in Brazilian Portuguese
    And the device language override is cleared

  Scenario: An unsupported device language falls back to English
    Given the device language is Japanese
    And the app is launched with empty storage and mocked preferences
    Then the home title is shown in English
    And the device language override is cleared

  Scenario: Choosing Spanish in settings applies immediately
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I choose the Spanish language
    Then the settings screen is shown in Spanish
    And the device language override is cleared

  Scenario: The chosen language survives a relaunch
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I choose the Spanish language
    And the app relaunches reading the same preferences
    Then the home title is shown in Spanish
    And the device language override is cleared

  Scenario: System default returns to the device language
    Given the device language is German
    And the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I choose the Spanish language
    And I choose the system default language
    Then the settings screen is shown in German
    And the device language override is cleared
