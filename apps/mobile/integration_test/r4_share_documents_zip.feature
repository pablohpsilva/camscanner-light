Feature: Share multiple documents as a zip

  Scenario: Select two documents and share them as a single zip
    Given two documents with real page images were saved to persistent storage earlier
    When the app launches reading that same storage
    And I long press the first document
    And I select the second document
    And I export the selection
    Then a zip is handed to the share sheet
