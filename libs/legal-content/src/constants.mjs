import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/** The three documents. Order is the order they appear in Settings. */
export const DOCS = ['terms', 'privacy', 'faq']

/** Must equal kSupportedAppLocales in apps/mobile/lib/l10n/locale_resolution.dart. */
export const LOCALES = ['en', 'pt', 'pt_BR', 'es', 'fr', 'de', 'lb', 'tr', 'ru', 'zh', 'ar']

export const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
export const repoRoot = resolve(packageRoot, '..', '..')
export const contentDir = resolve(packageRoot, 'content')

/** App/content tags use `_`; the web uses BCP-47 `-`. */
export const webTag = (locale) => locale.replace('_', '-')
