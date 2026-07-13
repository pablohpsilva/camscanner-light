Feature: Organizing documents

  Scenario: Move a document to a folder from its menu
    Given the library has a document "Invoice" with no folder
    And the library organize screen is showing
    When I move the document "Invoice" to a new folder "Work"
    Then the document "Invoice" appears under the folder "Work"

  Scenario: Add a tag to a document from its menu
    Given the library has a document "Invoice" with no tags
    And the library organize screen is showing
    When I add the tag "Important" to the document "Invoice"
    Then the document "Invoice" shows a tag chip "Important"
