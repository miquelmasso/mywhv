# mywhv

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firebase Functions

- Desplegar la callable: `firebase deploy --only functions`
- Llistar-les per verificar: `firebase functions:list`
- Assegura que el `projectId` de Flutter (`Firebase.app().options.projectId`) coincideix amb el projecte on es despleguen les functions.
- Regió usada al backend: `australia-southeast1`.

## Reports

- L'app guarda els reports directament a Firestore, a la col·lecció `reports`
- Això funciona sense ordinador obert ni backend local
- El límit actual és de `3` reports per dispositiu cada `24h`
- `report-backend/` queda com a backend local opcional de desenvolupament, però l'app ja no en depèn per enviar reports
