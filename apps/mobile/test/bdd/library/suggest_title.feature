Feature: Suggested title from OCR text

  Scenario: Opening rename shows a suggestion that fills the name
    Given the library has a document "Scan 1" whose page has OCR text suggesting "INVOICE"
    And the library organize screen is showing
    When I open the rename menu for the first document
    Then the rename dialog shows a suggestion "INVOICE"
    When I tap the rename suggestion
    Then the rename field shows "INVOICE"
