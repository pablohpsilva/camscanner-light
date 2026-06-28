import 'dart:io';

/// Shared handle to the on-disk DB file + documents dir used by the Tier-2
/// restart scenario, so the seed step and the relaunch step target the SAME
/// storage. Set by the seed step, read by the relaunch step.
File? persistentDbFile;
Directory? persistentDir;
