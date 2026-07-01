Feature: View and copy recognized text

  Scenario: Open a page's recognized text and copy it
    Given a saved document with recognized text {'HELLO WORLD'}
    When I open the first document
    And I open the text view
    Then I see {'HELLO WORLD'} text
    And I copy the recognized text
    Then I see {'Copied'} text
