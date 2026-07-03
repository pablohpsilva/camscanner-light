Feature: Multi-word content search ranks and spans pages
  Scenario: A query whose words are on different pages still finds the document
    Given a saved document "Report" with page 1 text "ACME corporation" and page 3 text "final INVOICE"
    And a saved document "Decoy" with page 1 text "acme only, nothing else"
    And the app launches reading that same storage
    When I open search and type "acme invoice"
    Then I see the document "Report"
    And I do not see the document "Decoy"
