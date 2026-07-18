// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../step/the_tip_jar_has_products.dart';
import './../step/i_tap_the_small_tip.dart';
import '../step/i_see_the_tip_thankyou_dialog.dart';
import './../step/the_tip_jar_has_no_products.dart';
import './../step/i_see_the_tip_unavailable_message.dart';

void main() {
  group('''iOS tip jar''', () {
    testWidgets('''Successful tip shows a thank-you''', (tester) async {
      await theTipJarHasProducts(tester);
      await iTapTheSmallTip(tester);
      await iSeeTheTipThankyouDialog(tester);
    });
    testWidgets('''Store unavailable''', (tester) async {
      await theTipJarHasNoProducts(tester);
      await iSeeTheTipUnavailableMessage(tester);
    });
  });
}
