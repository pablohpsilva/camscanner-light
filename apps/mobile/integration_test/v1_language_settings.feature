Feature: Choose the app language on a device

  Scenario: Spanish applies immediately and survives a relaunch
    Given the app is launched with camera permission granted and empty persistent storage
    When I open settings from home
    And I choose the Spanish language
    Then the settings screen is shown in Spanish
    When I navigate back to home
    And the app launches reading that same storage
    And I open settings from home
    Then the settings screen is shown in Spanish
    And I choose the system default language

  Scenario: Arabic lays the app out right-to-left
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I choose the Arabic language
    Then the app is laid out right-to-left
    And I choose the system default language
