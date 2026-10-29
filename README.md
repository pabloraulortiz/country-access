# Country Access

App Flutter (Android/iOS) + Supabase (PostgreSQL online) para control de acceso de un country.

## Puesta en marcha

1. Crear proyecto en supabase.com. En **SQL Editor** ejecutar, en orden:
   `schema.sql`, `002_morosidad.sql`, `003_admin_abm.sql`, `004_morosidad_mes.sql`, `005_turnos.sql`, `006_fotos_storage.sql`, `007_turno_dni_rondas.sql`
2. Crear el country y el primer admin (único alta manual; el resto se hace desde la app):
   ```sql
   insert into countries(name) values ('Mi Country') returning id;   -- crea también los 3 turnos
   -- crear usuario en Authentication > Users, copiar su UUID:
   insert into profiles(id, country_id, role, full_name, email)
   values ('<UUID_USUARIO>', '<ID_COUNTRY>', 'admin', 'Administrador', '<email>');
   ```
3. Edge Functions (Supabase CLI):
   ```
   supabase functions deploy admin-users
   supabase functions deploy send-push --no-verify-jwt
   ```
4. Editar `lib/config.dart` con la URL y la anon key.
5. `flutter create .` en la carpeta (genera android/ios), luego `flutter pub get`.
6. Permisos:
   - Android `AndroidManifest.xml`: `CAMERA`, `POST_NOTIFICATIONS`.
   - iOS `Info.plist`: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`.
   - La lectura de patente usa ML Kit: en iOS requiere deployment target 15.5 o superior (`ios/Podfile`).
7. `flutter run`.

## Push (FCM)
1. Firebase Console: crear proyecto, agregar app Android (`google-services.json` en `android/app/`) y iOS (`GoogleService-Info.plist` en `ios/Runner/`).
2. iOS: subir la clave APNs en Firebase (Project settings > Cloud Messaging) y activar *Push Notifications* y *Background Modes > Remote notifications* en Xcode.
3. Firebase > Project settings > Service accounts > generar clave privada (JSON), y:
   ```
   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)" WEBHOOK_SECRET=<clave-larga>
   ```
4. Supabase Dashboard > Database > Webhooks (HTTP Request a la Edge Function `send-push`, header `x-webhook-secret` = WEBHOOK_SECRET):
   - `live_requests`: Insert y Update
   - `panic_events`: Insert
   - `patrol_reports`: Insert (avisa a los admin cuando hay una novedad)

Sin Firebase configurado la app funciona igual, sin notificaciones.

## Roles
- **admin**: lotes, usuarios (alta, fotos, lotes, contraseña, activar/desactivar), morosidad del mes, turnos, lista de bloqueo (ícono en la barra superior), bitácora, alerta de pánico.
- **guard**: escanear QR, ingreso/egreso manual, consulta en vivo al propietario, pánico, ve su turno y compañeros con foto.
- **owner**: visitas (única/rango/recurrente/servicio), QR, autorizar/rechazar en vivo, historial.

## Turnos
Día 07:00–19:00 (2 guardias), Noche 19:00–07:00 (2), Rondín 22:00–06:00 (1). La fecha de un turno es la del día en que empieza. Desde Turnos: asignar por día, copiar del día anterior, repetir 6 días.

## Fotos
Bucket privado `profile-photos` (ruta `<country_id>/<user_id>.jpg`). Solo el admin sube o cambia fotos; admin y guardias las ven con URL firmada.

## Turno obligatorio
La guardia solo puede escanear, buscar por DNI/patente, registrar movimientos, consultar al propietario y cargar rondas **durante su turno asignado** (15 min antes del inicio hasta 30 min después del fin). Fuera de turno ve una pantalla de bloqueo; el botón de pánico sigue funcionando. Se valida en el servidor, no solo en la app. Se activa o desactiva desde Turnos ("Exigir turno asignado").
**Antes de usarlo en producción:** cargá los turnos de la semana, si no nadie podrá operar.
Las **salidas** nunca se bloquean: siempre se registran.

## Identificación por DNI o patente
En la pestaña Identificar la guardia escanea el código de barras del DNI (o escribe el DNI), y/o saca una foto a la patente (o la escribe). El sistema busca visitas autorizadas vigentes para ese DNI/patente y las valida como si fuera el QR. Si hay varias, elige; si no hay ninguna, consulta al propietario.
El lector del DNI entiende el formato actual del código PDF417 (campos separados por `@`); si no lo reconoce, se carga a mano.

## Rondas
La guardia del rondín (o cualquiera con turno) registra "Ronda sin novedad" o una novedad con texto y lote opcional. Los admin las ven en Bitácora > Rondas y reciben push cuando hay novedad.

## Pendiente
- Fotos en las novedades de ronda.
- Barrera / molinete, modo offline.
- Programar `select expire_visits();` y `select recompute_all_debts();` con pg_cron.

## Probar en un iPhone
Requiere una Mac con Xcode (Flutter no compila iOS desde Windows/Linux).
1. En la carpeta del proyecto: `flutter create .`, luego `./tools/setup_platforms.sh`, luego `flutter pub get`.
2. Editar `lib/config.dart` (URL y anon key de Supabase).
3. iPhone: Ajustes > Privacidad y seguridad > Modo desarrollador (activar y reiniciar). Conectarlo por cable y confiar en la Mac.
4. `open ios/Runner.xcworkspace`, en *Signing & Capabilities* elegir tu Apple ID como Team y un Bundle Identifier propio.
5. `flutter run` (con el iPhone elegido). Con Apple ID gratuito la app caduca a los 7 días; el push (APNs) requiere cuenta Apple Developer paga.
Sin Mac: compilar en la nube (Codemagic o GitHub Actions con runner macOS); para instalar en un iPhone real hace falta Apple Developer (TestFlight).

## Probar en iPhone sin Mac ni cuenta Apple (versión web, gratis)
La app corre como página web instalable (Safari > Compartir > Agregar a pantalla de inicio). Limitaciones: sin notificaciones push y sin lectura de patente por foto (se escribe); el lector de DNI por cámara depende de Safari.
1. Supabase: crear proyecto gratis, ejecutar los SQL en orden, crear country y admin, y pegar `supabase/functions/admin-users/index.ts` en Edge Functions > New function (nombre `admin-users`). Anotar *Project URL* y *anon public key* (Settings > API).
2. GitHub: crear un repositorio **público** y subir el contenido de la carpeta (incluye `.github/workflows/web.yml`).
3. Repo > Settings > Secrets and variables > Actions > **Variables**: `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
4. Repo > Settings > Pages > Source: **GitHub Actions**.
5. Repo > Actions > "Publicar app web" > Run workflow. En unos minutos queda en `https://<usuario>.github.io/<repo>/`.

## Android (APK por GitHub Actions, sin instalar nada)
Mismos pasos 1–3 de la versión web (Supabase + repo + variables). Luego: Actions > "Compilar APK Android" > Run workflow > al terminar, descargar el artefacto `country-access-apk` (zip con `app-release.apk`), pasarlo al celular e instalarlo (permitir "instalar apps desconocidas"). Push: requiere Firebase (`google-services.json`); sin eso la app funciona igual pero sin notificaciones.
