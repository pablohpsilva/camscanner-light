Feature: Rename a document

  Scenario: Rename a document from the library list
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I open the rename menu for the first document
    And I rename the document to {'Field Notes'}
    Then I see {'Field Notes'} text
