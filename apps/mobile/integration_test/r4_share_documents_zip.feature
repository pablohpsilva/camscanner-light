Feature: Share multiple documents as a zip

  Scenario: Select two documents and share them as a single zip
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I long press the first document
    And I select the second document
    And I export the selection
    Then a zip is handed to the share sheet
