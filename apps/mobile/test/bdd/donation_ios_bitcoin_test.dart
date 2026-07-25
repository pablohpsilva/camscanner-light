// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../step/the_ios_tip_jar_with_bitcoin_enabled_is_shown.dart';
import './../step/i_see_the_tip_buttons.dart';
import './../step/i_see_the_bitcoin_donation_section_after_the_tips.dart';
import './../step/i_do_not_see_the_kofi_button.dart';
import './../step/the_ios_tip_jar_with_bitcoin_disabled_is_shown.dart';
import './../step/i_do_not_see_the_bitcoin_donation_section.dart';

void main() {
  group('''iOS Bitcoin donation after tips''', () {
    testWidgets('''iOS shows Bitcoin after tips when enabled''',
        (tester) async {
      await theIosTipJarWithBitcoinEnabledIsShown(tester);
      await iSeeTheTipButtons(tester);
      await iSeeTheBitcoinDonationSectionAfterTheTips(tester);
      await iDoNotSeeTheKofiButton(tester);
    });
    testWidgets('''iOS hides Bitcoin when disabled''', (tester) async {
      await theIosTipJarWithBitcoinDisabledIsShown(tester);
      await iSeeTheTipButtons(tester);
      await iDoNotSeeTheBitcoinDonationSection(tester);
    });
  });
}
