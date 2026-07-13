Feature: Folder filtering

  Scenario: Filter documents by folder
    Given the library has a document "Invoice" in folder "Work"
    And the library has a document "Recipe" with no folder
    And the library home screen is showing
    When I tap the folder chip "Work"
    Then I see the document "Invoice"
    And I do not see the document "Recipe"
