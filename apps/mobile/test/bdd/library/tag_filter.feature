Feature: Tag filtering

  Scenario: Filter documents by tag
    Given the library has a document "Invoice" tagged "Work"
    And the library has a document "Recipe" with no tags
    And the library home screen is showing with tagged documents
    When I open the tag filter and select "Work"
    Then I see the document "Invoice"
    And I do not see the document "Recipe"
