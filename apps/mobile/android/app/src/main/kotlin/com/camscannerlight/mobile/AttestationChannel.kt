package com.camscannerlight.mobile

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Registers the `camscanner/attestation` method channel and handles the
 * `attest` method using the Google Play Integrity API.
 *
 * Phase-2 note: [CLOUD_PROJECT_NUMBER] must be set to the Google Cloud project
 * number linked in the Play Console (Play Integrity → cloud project). With the
 * placeholder value of `0L` the request is rejected by Play and
 * [addOnFailureListener] fires, returning `null` → Turnstile fallback.
 * This is the correct Phase-1 behaviour.
 *
 * The token returned to Dart is the raw Play Integrity token; the server
 * decodes it via the Play Integrity API (Phase-2 GCP setup).
 */
object AttestationChannel {
    private const val CHANNEL_NAME = "camscanner/attestation"

    /**
     * TODO(Phase-2): Replace with the Google Cloud project number linked in
     * Play Console → Play Integrity. Leave as 0L for Phase-1; this causes Play
     * to reject every request, so the failure listener returns null and the app
     * falls back to Turnstile (the correct Phase-1 behaviour).
     */
    private const val CLOUD_PROJECT_NUMBER = 0L

    fun register(context: Context, messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            if (call.method != "attest") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val challenge = call.argument<String>("challenge")
            if (challenge == null) {
                // Malformed call → fall back to Turnstile.
                result.success(null)
                return@setMethodCallHandler
            }
            performAttest(context, challenge, result)
        }
    }

    private fun performAttest(context: Context, challenge: String, result: MethodChannel.Result) {
        val manager = IntegrityManagerFactory.create(context)
        val request = IntegrityTokenRequest.builder()
            .setNonce(challenge)
            .setCloudProjectNumber(CLOUD_PROJECT_NUMBER)
            .build()

        manager.requestIntegrityToken(request)
            .addOnSuccessListener { response ->
                // Result callbacks from the Play Integrity task run on the main
                // thread, so no explicit runOnUiThread is required here.
                result.success(mapOf("token" to response.token()))
            }
            .addOnFailureListener {
                // Any error (misconfigured project, no Play Services, rooted
                // device, etc.) → return null so the app falls back to Turnstile.
                result.success(null)
            }
    }
}
