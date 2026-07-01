Feature: Search the library by content

  Scenario: Find a document by the text inside it
    Given a saved document named {'Untitled'} with page text {'INVOICE 2026'}
    When the app launches reading that same storage
    And I search for {'invoice'}
    Then I see {'Untitled'} text
    When I search for {'zzz'}
    Then I see the no matches message
