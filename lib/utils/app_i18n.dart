import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppI18n {
  const AppI18n._();

  static const String prefsLanguageKey = 'guide_lang';

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'common.close': 'Close',
      'common.clear': 'Clear',
      'common.ok': 'OK',
      'common.yes': 'Yes',
      'common.retry': 'Retry',
      'common.try_again': 'Try again',
      'common.report_problem': 'Report a problem',
      'common.next_step': 'Next step',
      'common.what_can_you_do': 'What can you do?',
      'common.copy_code': 'Copy code',
      'common.discount_code': 'Discount code',
      'guide.title': 'Australia Guide',
      'guide.search_hint': 'Search anything',
      'guide.select_language': 'Select language',
      'guide.change_language': 'Change language',
      'guide.no_results': 'No results found',
      'guide.no_sections': 'No sections found.',
      'guide.load_error': 'We could not load the guide.',
      'journey.title': 'Your Australia Journey',
      'journey.progress': 'Journey progress',
      'journey.checklist': 'Australia checklist',
      'journey.open_full_guide': 'Open full guide',
      'journey.completed': 'Completed',
      'journey.go_full_guide': 'Go to full guide',
      'journey.recommended_tools': 'Recommended tools/resources',
      'journey.recommended': 'Recommended',
      'journey.useful_resources': 'Useful resources',
      'journey.mark_completed': 'Mark as completed',
      'journey.tasks_checked': 'tasks checked',
      'journey.tasks_done': 'tasks done',
      'journey.open': 'Open',
      'journey.done': 'Done',
      'journey.completed_title': 'Nice! Journey completed',
      'journey.completed_body':
          'You now know where the important WorkyDay guide sections live.',
      'journey.message_completed':
          'Nice! One step closer to your Working Holiday adventure.',
      'journey.message_start':
          'Hey mate! Let’s get you ready for Australia 🇦🇺',
      'journey.mascot_checklist':
          'Now use this as your Australia checklist. Tick things off as you go.',
      'journey.mascot_start':
          'First things first: visa, arrival and basic setup.',
      'journey.step.visa_requirements.title': 'Visa & requirements',
      'journey.step.visa_requirements.description':
          'Learn which visa fits you before travelling.',
      'journey.step.visa_requirements.tip':
          'Start here. Everything else depends on your visa path.',
      'journey.step.visa_requirements.bullet.0':
          'Compare WHV and Student Visa paths',
      'journey.step.visa_requirements.bullet.1':
          'Check age, passport and country rules',
      'journey.step.visa_requirements.bullet.2':
          'Review funds, insurance and documents',
      'journey.step.visa_requirements.bullet.3':
          'Use official sources before applying',
      'journey.step.before_arrival.title': 'Before arrival',
      'journey.step.before_arrival.description':
          'Prepare insurance, flights, money and your first plan.',
      'journey.step.before_arrival.tip':
          'A tiny bit of prep now saves a lot of stress later.',
      'journey.step.before_arrival.bullet.0': 'Plan your first city and season',
      'journey.step.before_arrival.bullet.1':
          'Book flights and first nights early',
      'journey.step.before_arrival.bullet.2':
          'Prepare money, cards and travel cover',
      'journey.step.before_arrival.bullet.3':
          'Set up internet for when you land',
      'journey.step.arrival_steps.title': 'Arrival & paperwork',
      'journey.step.arrival_steps.description':
          'Set up TFN, SIM card and key documents.',
      'journey.step.arrival_steps.tip':
          'Do the boring setup once, then Australia gets easier.',
      'journey.step.arrival_steps.bullet.0': 'Get connected with SIM or e-sim',
      'journey.step.arrival_steps.bullet.1': 'Apply for your TFN correctly',
      'journey.step.arrival_steps.bullet.2':
          'Open a bank account and keep details safe',
      'journey.step.arrival_steps.bullet.3':
          'Save certificates and important paperwork',
      'journey.step.housing.title': 'Housing',
      'journey.step.housing.description':
          'Discover where backpackers usually stay.',
      'journey.step.housing.tip':
          'First nights are about location, flexibility and safety.',
      'journey.step.housing.bullet.0': 'Start with hostels or short stays',
      'journey.step.housing.bullet.1':
          'Compare location, transport and weekly price',
      'journey.step.housing.bullet.2': 'Avoid sending deposits too quickly',
      'journey.step.housing.bullet.3': 'Use housing groups carefully',
      'journey.step.work.title': 'Jobs',
      'journey.step.work.description': 'Learn how to find work and apply.',
      'journey.step.work.tip':
          'Apply wide, follow up fast, and keep your CV simple.',
      'journey.step.work.bullet.0': 'Prepare a simple Australian-style CV',
      'journey.step.work.bullet.1': 'Apply online and in person',
      'journey.step.work.bullet.2': 'Follow up with managers quickly',
      'journey.step.work.bullet.3': 'Keep track of applications and contacts',
      'journey.step.regional_and_extension.title': 'Regional farm work',
      'journey.step.regional_and_extension.description':
          'Understand regional jobs and second-year visa basics.',
      'journey.step.regional_and_extension.tip':
          'Check postcode eligibility before committing to a job.',
      'journey.step.regional_and_extension.bullet.0':
          'Check if the postcode counts',
      'journey.step.regional_and_extension.bullet.1':
          'Understand eligible industries and tasks',
      'journey.step.regional_and_extension.bullet.2':
          'Track payslips and work dates',
      'journey.step.regional_and_extension.bullet.3':
          'Avoid unclear cash-in-hand offers',
      'journey.step.transport.title': 'Vehicle',
      'journey.step.transport.description':
          'Buying, renting or travelling around Australia.',
      'journey.step.transport.tip':
          'A car can be freedom, but paperwork matters.',
      'journey.step.transport.bullet.0': 'Compare car, van, bus and flights',
      'journey.step.transport.bullet.1':
          'Check rego, insurance and roadworthy rules',
      'journey.step.transport.bullet.2': 'Budget for fuel, repairs and tolls',
      'journey.step.transport.bullet.3': 'Plan long drives with safety stops',
      'journey.step.money_taxes.title': 'Wages, taxes & super',
      'journey.step.money_taxes.description':
          'Understand payslips, taxes and superannuation.',
      'journey.step.money_taxes.tip':
          'Know your pay rate and keep every payslip.',
      'journey.step.money_taxes.bullet.0': 'Know your minimum pay rate',
      'journey.step.money_taxes.bullet.1':
          'Read payslips before accepting problems',
      'journey.step.money_taxes.bullet.2': 'Understand tax and super basics',
      'journey.step.money_taxes.bullet.3':
          'Keep records for refunds and claims',
      'journey.step.visa_requirements.check.0':
          'Choose WHV or Student Visa path',
      'journey.step.visa_requirements.check.1': 'Check passport validity',
      'journey.step.visa_requirements.check.2':
          'Review visa requirements for your country',
      'journey.step.visa_requirements.check.3':
          'Check English/IELTS requirement if applicable',
      'journey.step.visa_requirements.check.4':
          'Prepare health insurance if required',
      'journey.step.visa_requirements.check.5': 'Prepare proof of funds',
      'journey.step.visa_requirements.check.6':
          'Prepare education documents if applicable',
      'journey.step.visa_requirements.check.7':
          'Create or access your ImmiAccount',
      'journey.step.visa_requirements.check.8':
          'Save official immigration links',
      'journey.step.before_arrival.check.0': 'Compare travel insurance options',
      'journey.step.before_arrival.check.1': 'Book your flight to Australia',
      'journey.step.before_arrival.check.2': 'Book your first nights',
      'journey.step.before_arrival.check.3':
          'Download offline maps for arrival',
      'journey.step.before_arrival.check.4':
          'Prepare travel card or bank backup',
      'journey.step.before_arrival.check.5':
          'Choose an e-sim or arrival SIM plan',
      'journey.step.before_arrival.check.6': 'Save important documents offline',
      'journey.step.before_arrival.check.7': 'Plan airport to hostel transport',
      'journey.step.arrival_steps.check.0': 'Activate SIM or e-sim',
      'journey.step.arrival_steps.check.1': 'Apply for TFN',
      'journey.step.arrival_steps.check.2': 'Open or prepare a bank account',
      'journey.step.arrival_steps.check.3': 'Set up Super account details',
      'journey.step.arrival_steps.check.4':
          'Get Australian phone number ready for forms',
      'journey.step.arrival_steps.check.5': 'Save passport and visa copies',
      'journey.step.arrival_steps.check.6': 'Organise certificates and IDs',
      'journey.step.arrival_steps.check.7': 'Store emergency contacts',
      'journey.step.housing.check.0': 'Book first hostel or short stay',
      'journey.step.housing.check.1': 'Join local housing groups',
      'journey.step.housing.check.2': 'Check transport before choosing an area',
      'journey.step.housing.check.3': 'Prepare deposit budget',
      'journey.step.housing.check.4': 'Avoid paying before verifying the place',
      'journey.step.housing.check.5': 'Inspect the room before committing',
      'journey.step.housing.check.6': 'Confirm bills and bond conditions',
      'journey.step.housing.check.7': 'Keep written proof of payments',
      'journey.step.work.check.0': 'Prepare Australian-style CV',
      'journey.step.work.check.1': 'Create a simple job tracker',
      'journey.step.work.check.2': 'Prepare a short cover message',
      'journey.step.work.check.3': 'Apply online',
      'journey.step.work.check.4': 'Hand out CVs in person',
      'journey.step.work.check.5': 'Follow up with managers',
      'journey.step.work.check.6': 'Save references and certificates',
      'journey.step.work.check.7': 'Check pay rate before accepting',
      'journey.step.regional_and_extension.check.0': 'Check eligible postcode',
      'journey.step.regional_and_extension.check.1':
          'Confirm eligible industry and task',
      'journey.step.regional_and_extension.check.2': 'Save payslips',
      'journey.step.regional_and_extension.check.3':
          'Track days and employer details',
      'journey.step.regional_and_extension.check.4':
          'Keep signed timesheets if possible',
      'journey.step.regional_and_extension.check.5':
          'Confirm ABN or employer details',
      'journey.step.regional_and_extension.check.6':
          'Avoid unclear cash-only offers',
      'journey.step.regional_and_extension.check.7':
          'Back up evidence for second-year visa',
      'journey.step.transport.check.0': 'Compare transport options',
      'journey.step.transport.check.1': 'Check rego and insurance',
      'journey.step.transport.check.2': 'Inspect vehicle before buying',
      'journey.step.transport.check.3': 'Check PPSR/VIN before buying',
      'journey.step.transport.check.4': 'Confirm roadworthy rules by state',
      'journey.step.transport.check.5': 'Budget fuel and repairs',
      'journey.step.transport.check.6': 'Prepare emergency kit and spare tyre',
      'journey.step.transport.check.7': 'Plan long drives safely',
      'journey.step.money_taxes.check.0': 'Learn your minimum pay rate',
      'journey.step.money_taxes.check.1': 'Check each payslip',
      'journey.step.money_taxes.check.2': 'Keep tax records',
      'journey.step.money_taxes.check.3':
          'Confirm your TFN is given to employers',
      'journey.step.money_taxes.check.4': 'Check super is being paid',
      'journey.step.money_taxes.check.5': 'Save superannuation details',
      'journey.step.money_taxes.check.6': 'Keep bank and employer records',
      'journey.step.money_taxes.check.7': 'Prepare for tax return season',
      'kangaroo.bubble': 'Let me guide you through Australia 🇦🇺',
      'visa.types.title': 'Visa & requirements',
      'visa.types.heading': 'Types of visa',
      'visa.types.whv': 'Work and Holiday Visa',
      'visa.types.student': 'Student Visa',
      'visa.whv.b1': 'Travel and work full-time',
      'visa.whv.b2': 'Change employers freely',
      'visa.whv.b3': 'Explore Australia while saving',
      'visa.whv.b4': 'Valid for adventure and work',
      'visa.whv.b5': 'Good for short-term plans',
      'visa.student.b1': 'Study at schools, TAFE or uni',
      'visa.student.b2': 'Work limited hours',
      'visa.student.b3': 'Build a longer-term future',
      'visa.student.b4': 'Improve English or skills',
      'visa.student.b5': 'Best for study-based plans',
      'student.title': 'Student Visa',
      'student.what_title': 'What is a Student Visa?',
      'student.what_1':
          'Designed for people enrolled in an eligible course in Australia.',
      'student.what_2':
          'Allows study at schools, TAFE, universities or other approved providers.',
      'student.what_3': 'Lets students work limited hours while studying.',
      'student.approval_title': 'Estimated approval time',
      'student.approval_body':
          'Processing times vary depending on your course, country, documents and application quality.',
      'student.requirements_title': 'Student Visa requirements',
      'student.req_1': 'Valid passport',
      'student.req_2': 'Confirmation of Enrolment from an approved provider',
      'student.req_3':
          'Evidence of funds for course fees, travel and living costs',
      'student.req_4': 'Health insurance for overseas students',
      'student.req_5': 'English level or education documents if required',
      'student.important_title': 'Important',
      'student.important_body':
          'Student visa rules and work conditions can change. Always verify the latest requirements on the official Australian Government website before applying.',
      'student.apply_tab': 'How to apply',
      'student.requirements_tab': 'Requirements',
      'student.steps_title': 'Application steps',
      'student.step_1': 'Choose an eligible course and education provider.',
      'student.step_2': 'Receive your Confirmation of Enrolment.',
      'student.step_3':
          'Prepare documents, funds evidence and health insurance.',
      'student.step_4': 'Apply online through ImmiAccount.',
      'student.step_5': 'Wait for the visa decision before making final plans.',
      'student.balance_title': 'Work and study balance',
      'student.balance_body':
          'Plan your budget around study first. Work rights are limited and should not be treated as the only way to fund your stay.',
      'student.support_title': 'Student visa support',
      'student.support_body':
          'If you need help applying for a student visa or finding schools and study centres in Australia, we recommend contacting YouTooProject.',
      'student.official_title': 'Official information',
      'student.official_button': 'Check Student Visa details',
      'student.support_button': 'YouTooProject',
      'insurance.title': 'Travel Insurance',
      'insurance.recommended': 'Recommended insurance',
      'insurance.compare': 'Compare WHV insurance',
      'flights.title': 'Flights',
      'flights.buy': 'Buy your flights',
      'hostels.where': 'Where to book hostels',
      'banks.title': 'International banks',
      'banks.suggested': 'Suggested international banks',
      'banks.go_n26': 'Go to N26',
      'esims.popular': 'Popular e-sims',
      'resource.insurance.subtitle': 'Compare useful travel insurance options.',
      'resource.youtoo.subtitle': 'Student visa and study support.',
      'resource.flights.subtitle': 'Useful flight booking partners.',
      'resource.hostels.subtitle': 'Find your first nights in Australia.',
      'resource.banks.subtitle': 'Cards and accounts for arrival.',
      'resource.esims.subtitle': 'Internet ready when you land.',
      'donation.title': 'Support WorkyDay',
      'donation.body':
          'WorkyDay is free and built for Working Holiday travellers in Australia. If it helped you, you can support the project.',
      'donation.button': 'Buy me a coffee ☕',
      'profile.automatic_email': 'Automatic email editing',
      'profile.favourites': 'Favourites',
      'profile.send_report': 'Send report',
      'profile.support': 'Buy me a coffee',
      'profile.title': 'Profile',
      'profile.settings': 'Profile settings',
      'profile.settings_body':
          'Set up automatic email, favourites and app tools.',
      'map.place_unknown': 'Unknown place',
      'map.google_paused': 'Google Maps is temporarily paused.',
      'map.dialog.profile': 'Profile',
      'map.error.invalid_place': 'This place has no valid ID.',
      'map.worked.title': 'Have you worked here?',
      'map.worked.subtitle': 'Your feedback helps other users.',
      'map.worked.no': 'No',
      'map.worked.already_title': 'Already marked',
      'map.worked.already_body': 'This place is already in your worked list.',
      'map.worked.saved_local': 'Saved on this device. Sync can happen later.',
      'map.email.copy': 'Copy email',
      'map.email.send': 'Send email',
      'map.email.copied': 'Email copied',
      'map.location.denied': 'Location access denied. Tap again to allow it.',
      'map.location.services_off': 'Location services are turned off.',
      'map.location.settings': 'Settings',
      'map.location.unavailable': 'We could not get your location right now.',
      'map.location.blocked':
          'Location access is blocked. Open settings and allow Location.',
      'map.location.settings_failed': 'Could not open location settings.',
      'map.tooltip.worked_here': 'I worked here',
      'map.tooltip.copy_phone': 'Copy phone',
      'map.tooltip.email_options': 'Email options',
      'map.tooltip.open_facebook': 'Open Facebook',
      'map.tooltip.view_jobs': 'View job offers',
      'map.tooltip.open_instagram': 'Open Instagram',
      'map.tooltip.add_favourite': 'Add to favourites',
      'map.tooltip.remove_favourite': 'Remove from favourites',
      'map.tooltip.directions': 'Directions',
      'map.filter.title': 'Filters',
      'map.filter.show_without_contact': 'Show places without web or contact',
      'favorites.empty': 'No favourites yet',
      'favorites.load_error':
          'We could not load your favourites right now. Please try again.',
      'review.title': 'Are you enjoying WorkyDay?',
      'review.body':
          'WorkyDay is just getting started. Rate the app and tell us your favourite feature.',
      'review.not_now': 'Not now',
      'review.rate_app': 'Rate app',
      'mail.save_message': 'Save message',
      'mail.message_hint': 'Write here your message...',
      'mail.email_content': 'Email content',
      'mail.upload_cv': 'Upload CV (PDF)',
      'mail.replace_cv': 'Replace CV (PDF)',
      'mail.current_cv': 'Current CV',
      'mail.no_cv': 'none',
      'forum.ask': 'Ask forum',
      'error.oops': 'Oops! ',
      'error.link_title': 'Link failed',
      'error.link_message': 'This link is not available right now.',
      'error.try_report': 'Try again later or report it.',
      'error.load_title': 'Didn\'t load',
      'error.load_message': 'Something went wrong. Please try again.',
      'error.email_title': 'Email failed',
      'error.email_message': 'We could not open your email app.',
      'error.email_helper': 'Check Mail setup or report it.',
      'onboarding.skip': 'Skip',
      'onboarding.welcome.title': 'Welcome to WorkyDay 👋',
      'onboarding.welcome.description':
          'Find jobs and useful info for your Working Holiday in Australia.\nLet’s do a quick tour.',
      'onboarding.welcome.primary': 'Start tour',
      'onboarding.map.title': 'Find workplaces around you',
      'onboarding.map.description':
          'Tap a place to view details and contact employers.',
      'onboarding.map.primary': 'Next',
      'onboarding.automatic_email.title': 'Contact employers faster',
      'onboarding.automatic_email.description':
          'Save your message and CV once, then send applications faster.',
      'onboarding.automatic_email.primary': 'Next',
      'onboarding.guide.title': 'Australia Guide',
      'onboarding.guide.description':
          'Everything you need for your Working Holiday:',
      'onboarding.guide.bullet.0': 'visa requirements',
      'onboarding.guide.bullet.1': 'jobs',
      'onboarding.guide.bullet.2': 'housing',
      'onboarding.guide.bullet.3': 'taxes and super',
      'onboarding.guide.primary': 'Next',
      'onboarding.guide_kangaroo.title': 'Your Australia journey',
      'onboarding.guide_kangaroo.description':
          'Tap the kangaroo to open the guided journey and checklist.',
      'onboarding.guide_kangaroo.primary': 'Finish',
    },
    'es': {
      'common.close': 'Cerrar',
      'common.clear': 'Borrar',
      'common.ok': 'OK',
      'common.yes': 'Sí',
      'common.retry': 'Reintentar',
      'common.try_again': 'Intentar de nuevo',
      'common.report_problem': 'Reportar un problema',
      'common.next_step': 'Siguiente paso',
      'common.what_can_you_do': '¿Qué puedes hacer?',
      'common.copy_code': 'Copiar código',
      'common.discount_code': 'Código de descuento',
      'guide.title': 'Guía de Australia',
      'guide.search_hint': 'Buscar cualquier cosa',
      'guide.select_language': 'Selecciona idioma',
      'guide.change_language': 'Cambiar idioma',
      'guide.no_results': 'No se encontraron resultados',
      'guide.no_sections': 'No se encontraron secciones.',
      'guide.load_error': 'No pudimos cargar la guía.',
      'journey.title': 'Tu viaje por Australia',
      'journey.progress': 'Progreso del viaje',
      'journey.checklist': 'Checklist de Australia',
      'journey.open_full_guide': 'Abrir guía completa',
      'journey.completed': 'Completado',
      'journey.go_full_guide': 'Ir a la guía completa',
      'journey.recommended_tools': 'Herramientas recomendadas',
      'journey.recommended': 'Recomendado',
      'journey.useful_resources': 'Recursos útiles',
      'journey.mark_completed': 'Marcar como completado',
      'journey.tasks_checked': 'tareas marcadas',
      'journey.tasks_done': 'tareas hechas',
      'journey.open': 'Abrir',
      'journey.done': 'Listo',
      'journey.completed_title': '¡Bien! Viaje completado',
      'journey.completed_body':
          'Ahora sabes dónde están las secciones importantes de WorkyDay.',
      'journey.message_completed':
          '¡Genial! Un paso más cerca de tu aventura Working Holiday.',
      'journey.message_start': '¡Vamos! Te preparo para Australia 🇦🇺',
      'journey.mascot_checklist':
          'Ahora úsalo como checklist para Australia. Marca lo que vayas haciendo.',
      'journey.mascot_start': 'Primero: visa, llegada y configuración básica.',
      'journey.step.visa_requirements.title': 'Visado y requisitos',
      'journey.step.visa_requirements.description':
          'Aprende qué visado encaja contigo antes de viajar.',
      'journey.step.visa_requirements.tip':
          'Empieza aquí. Todo depende de tu tipo de visado.',
      'journey.step.visa_requirements.bullet.0': 'Compara WHV y Student Visa',
      'journey.step.visa_requirements.bullet.1':
          'Revisa edad, pasaporte y país',
      'journey.step.visa_requirements.bullet.2':
          'Prepara fondos, seguro y documentos',
      'journey.step.visa_requirements.bullet.3':
          'Consulta siempre fuentes oficiales',
      'journey.step.before_arrival.title': 'Antes de llegar',
      'journey.step.before_arrival.description':
          'Prepara seguro, vuelos, dinero y tu primer plan.',
      'journey.step.before_arrival.tip':
          'Un poco de preparación ahora evita mucho estrés después.',
      'journey.step.before_arrival.bullet.0':
          'Elige primera ciudad y temporada',
      'journey.step.before_arrival.bullet.1':
          'Reserva vuelos y primeras noches',
      'journey.step.before_arrival.bullet.2':
          'Prepara dinero, tarjetas y seguro',
      'journey.step.before_arrival.bullet.3': 'Ten internet listo al aterrizar',
      'journey.step.arrival_steps.title': 'Llegada y papeleo',
      'journey.step.arrival_steps.description':
          'Configura TFN, SIM y documentos clave.',
      'journey.step.arrival_steps.tip':
          'Haz el papeleo una vez y todo será más fácil.',
      'journey.step.arrival_steps.bullet.0': 'Activa SIM o e-sim',
      'journey.step.arrival_steps.bullet.1': 'Solicita el TFN correctamente',
      'journey.step.arrival_steps.bullet.2':
          'Abre una cuenta bancaria y guarda los datos',
      'journey.step.arrival_steps.bullet.3':
          'Organiza certificados y documentos',
      'journey.step.housing.title': 'Alojamiento',
      'journey.step.housing.description':
          'Descubre dónde suelen alojarse los backpackers.',
      'journey.step.housing.tip':
          'Las primeras noches van de ubicación, flexibilidad y seguridad.',
      'journey.step.housing.bullet.0': 'Empieza con hostels o estancias cortas',
      'journey.step.housing.bullet.1':
          'Compara zona, transporte y precio semanal',
      'journey.step.housing.bullet.2':
          'Evita enviar depósitos demasiado rápido',
      'journey.step.housing.bullet.3': 'Usa grupos de alojamiento con cuidado',
      'journey.step.work.title': 'Trabajo',
      'journey.step.work.description': 'Aprende a buscar trabajo y aplicar.',
      'journey.step.work.tip':
          'Aplica mucho, haz seguimiento rápido y mantén tu CV simple.',
      'journey.step.work.bullet.0': 'Prepara un CV estilo australiano',
      'journey.step.work.bullet.1': 'Aplica online y en persona',
      'journey.step.work.bullet.2': 'Haz seguimiento con managers',
      'journey.step.work.bullet.3': 'Lleva control de tus aplicaciones',
      'journey.step.regional_and_extension.title': 'Trabajo regional',
      'journey.step.regional_and_extension.description':
          'Entiende trabajos regionales y requisitos para segundo año.',
      'journey.step.regional_and_extension.tip':
          'Comprueba el postcode antes de aceptar un trabajo.',
      'journey.step.regional_and_extension.bullet.0':
          'Comprueba si el postcode cuenta',
      'journey.step.regional_and_extension.bullet.1':
          'Revisa industrias y tareas válidas',
      'journey.step.regional_and_extension.bullet.2':
          'Guarda payslips y fechas trabajadas',
      'journey.step.regional_and_extension.bullet.3':
          'Evita ofertas poco claras en efectivo',
      'journey.step.transport.title': 'Vehículo',
      'journey.step.transport.description':
          'Comprar, alquilar o moverte por Australia.',
      'journey.step.transport.tip':
          'Un coche da libertad, pero el papeleo importa.',
      'journey.step.transport.bullet.0': 'Compara coche, van, bus y vuelos',
      'journey.step.transport.bullet.1': 'Revisa rego, seguro y roadworthy',
      'journey.step.transport.bullet.2':
          'Calcula gasolina, reparaciones y peajes',
      'journey.step.transport.bullet.3': 'Planifica viajes largos con paradas',
      'journey.step.money_taxes.title': 'Salarios, impuestos y super',
      'journey.step.money_taxes.description':
          'Entiende payslips, impuestos y superannuation.',
      'journey.step.money_taxes.tip':
          'Conoce tu sueldo mínimo y guarda cada payslip.',
      'journey.step.money_taxes.bullet.0': 'Conoce tu sueldo mínimo',
      'journey.step.money_taxes.bullet.1': 'Revisa cada payslip',
      'journey.step.money_taxes.bullet.2':
          'Entiende impuestos y superannuation',
      'journey.step.money_taxes.bullet.3': 'Guarda registros para devoluciones',
      'journey.step.visa_requirements.check.0': 'Elegir WHV o Student Visa',
      'journey.step.visa_requirements.check.1':
          'Comprobar validez del pasaporte',
      'journey.step.visa_requirements.check.2':
          'Revisar requisitos de visado por país',
      'journey.step.visa_requirements.check.3':
          'Comprobar inglés/IELTS si aplica',
      'journey.step.visa_requirements.check.4':
          'Preparar seguro médico si hace falta',
      'journey.step.visa_requirements.check.5': 'Preparar prueba de fondos',
      'journey.step.visa_requirements.check.6':
          'Preparar documentos educativos si aplica',
      'journey.step.visa_requirements.check.7': 'Crear o acceder a ImmiAccount',
      'journey.step.visa_requirements.check.8':
          'Guardar enlaces oficiales de inmigración',
      'journey.step.before_arrival.check.0':
          'Comparar opciones de seguro de viaje',
      'journey.step.before_arrival.check.1': 'Reservar vuelo a Australia',
      'journey.step.before_arrival.check.2': 'Reservar las primeras noches',
      'journey.step.before_arrival.check.3':
          'Descargar mapas offline para la llegada',
      'journey.step.before_arrival.check.4':
          'Preparar tarjeta o banco de respaldo',
      'journey.step.before_arrival.check.5':
          'Elegir e-sim o SIM para la llegada',
      'journey.step.before_arrival.check.6':
          'Guardar documentos importantes offline',
      'journey.step.before_arrival.check.7':
          'Planificar transporte del aeropuerto al hostel',
      'journey.step.arrival_steps.check.0': 'Activar SIM o e-sim',
      'journey.step.arrival_steps.check.1': 'Solicitar TFN',
      'journey.step.arrival_steps.check.2': 'Abrir o preparar cuenta bancaria',
      'journey.step.arrival_steps.check.3':
          'Configurar datos de superannuation',
      'journey.step.arrival_steps.check.4':
          'Tener número australiano listo para formularios',
      'journey.step.arrival_steps.check.5':
          'Guardar copias de pasaporte y visado',
      'journey.step.arrival_steps.check.6': 'Organizar certificados e IDs',
      'journey.step.arrival_steps.check.7': 'Guardar contactos de emergencia',
      'journey.step.housing.check.0': 'Reservar hostel o estancia corta',
      'journey.step.housing.check.1': 'Unirse a grupos locales de alojamiento',
      'journey.step.housing.check.2':
          'Comprobar transporte antes de elegir zona',
      'journey.step.housing.check.3': 'Preparar presupuesto para depósito',
      'journey.step.housing.check.4':
          'Evitar pagar antes de verificar el lugar',
      'journey.step.housing.check.5':
          'Inspeccionar la habitación antes de comprometerte',
      'journey.step.housing.check.6':
          'Confirmar facturas y condiciones de bond',
      'journey.step.housing.check.7': 'Guardar prueba escrita de pagos',
      'journey.step.work.check.0': 'Preparar CV estilo australiano',
      'journey.step.work.check.1': 'Crear tracker simple de trabajos',
      'journey.step.work.check.2': 'Preparar mensaje corto de presentación',
      'journey.step.work.check.3': 'Aplicar online',
      'journey.step.work.check.4': 'Entregar CVs en persona',
      'journey.step.work.check.5': 'Hacer seguimiento con managers',
      'journey.step.work.check.6': 'Guardar referencias y certificados',
      'journey.step.work.check.7': 'Comprobar sueldo antes de aceptar',
      'journey.step.regional_and_extension.check.0':
          'Comprobar postcode elegible',
      'journey.step.regional_and_extension.check.1':
          'Confirmar industria y tarea elegible',
      'journey.step.regional_and_extension.check.2': 'Guardar payslips',
      'journey.step.regional_and_extension.check.3':
          'Registrar días y datos del empleador',
      'journey.step.regional_and_extension.check.4':
          'Guardar timesheets firmadas si puedes',
      'journey.step.regional_and_extension.check.5':
          'Confirmar ABN o datos del empleador',
      'journey.step.regional_and_extension.check.6':
          'Evitar ofertas solo en efectivo poco claras',
      'journey.step.regional_and_extension.check.7':
          'Hacer copia de pruebas para segundo año',
      'journey.step.transport.check.0': 'Comparar opciones de transporte',
      'journey.step.transport.check.1': 'Revisar rego y seguro',
      'journey.step.transport.check.2':
          'Inspeccionar vehículo antes de comprar',
      'journey.step.transport.check.3': 'Comprobar PPSR/VIN antes de comprar',
      'journey.step.transport.check.4': 'Confirmar roadworthy por estado',
      'journey.step.transport.check.5': 'Calcular gasolina y reparaciones',
      'journey.step.transport.check.6':
          'Preparar kit de emergencia y rueda de repuesto',
      'journey.step.transport.check.7':
          'Planificar viajes largos con seguridad',
      'journey.step.money_taxes.check.0': 'Aprender tu sueldo mínimo',
      'journey.step.money_taxes.check.1': 'Revisar cada payslip',
      'journey.step.money_taxes.check.2': 'Guardar registros fiscales',
      'journey.step.money_taxes.check.3':
          'Confirmar que tu TFN está dado al empleador',
      'journey.step.money_taxes.check.4': 'Comprobar que se paga tu super',
      'journey.step.money_taxes.check.5': 'Guardar datos de superannuation',
      'journey.step.money_taxes.check.6':
          'Guardar registros de banco y empleador',
      'journey.step.money_taxes.check.7':
          'Prepararte para la declaración de impuestos',
      'kangaroo.bubble': 'Déjame guiarte por Australia 🇦🇺',
      'visa.types.title': 'Visado y requisitos',
      'visa.types.heading': 'Tipos de visado',
      'visa.types.whv': 'Work and Holiday Visa',
      'visa.types.student': 'Student Visa',
      'visa.whv.b1': 'Viajar y trabajar a tiempo completo',
      'visa.whv.b2': 'Cambiar de empleador libremente',
      'visa.whv.b3': 'Explorar Australia mientras ahorras',
      'visa.whv.b4': 'Válido para aventura y trabajo',
      'visa.whv.b5': 'Bueno para planes de corta duración',
      'visa.student.b1': 'Estudiar en escuelas, TAFE o uni',
      'visa.student.b2': 'Trabajar horas limitadas',
      'visa.student.b3': 'Construir un futuro a largo plazo',
      'visa.student.b4': 'Mejorar inglés o habilidades',
      'visa.student.b5': 'Ideal para planes de estudio',
      'student.title': 'Student Visa',
      'student.what_title': '¿Qué es una Student Visa?',
      'student.what_1':
          'Diseñada para personas matriculadas en un curso elegible en Australia.',
      'student.what_2':
          'Permite estudiar en escuelas, TAFE, universidades u otros centros aprobados.',
      'student.what_3': 'Permite trabajar horas limitadas mientras estudias.',
      'student.approval_title': 'Tiempo estimado de aprobación',
      'student.approval_body':
          'Los tiempos varían según el curso, país, documentos y calidad de la solicitud.',
      'student.requirements_title': 'Requisitos de Student Visa',
      'student.req_1': 'Pasaporte válido',
      'student.req_2': 'Confirmation of Enrolment de un proveedor aprobado',
      'student.req_3': 'Prueba de fondos para curso, viaje y gastos de vida',
      'student.req_4': 'Seguro médico para estudiantes internacionales',
      'student.req_5':
          'Nivel de inglés o documentos educativos si se requieren',
      'student.important_title': 'Importante',
      'student.important_body':
          'Las reglas pueden cambiar. Verifica siempre los requisitos oficiales antes de aplicar.',
      'student.apply_tab': 'Cómo aplicar',
      'student.requirements_tab': 'Requisitos',
      'student.steps_title': 'Pasos de solicitud',
      'student.step_1': 'Elige un curso y proveedor elegibles.',
      'student.step_2': 'Recibe tu Confirmation of Enrolment.',
      'student.step_3': 'Prepara documentos, fondos y seguro médico.',
      'student.step_4': 'Aplica online mediante ImmiAccount.',
      'student.step_5': 'Espera la decisión antes de hacer planes finales.',
      'student.balance_title': 'Equilibrio entre trabajo y estudio',
      'student.balance_body':
          'Planifica tu presupuesto alrededor del estudio. El trabajo es limitado.',
      'student.support_title': 'Ayuda con Student Visa',
      'student.support_body':
          'Si necesitas ayuda con la visa o centros de estudio, recomendamos contactar con YouTooProject.',
      'student.official_title': 'Información oficial',
      'student.official_button': 'Ver detalles de Student Visa',
      'student.support_button': 'YouTooProject',
      'insurance.title': 'Seguro de viaje',
      'insurance.recommended': 'Seguro recomendado',
      'insurance.compare': 'Comparar seguro WHV',
      'flights.title': 'Vuelos',
      'flights.buy': 'Comprar vuelos',
      'hostels.where': 'Dónde reservar hostels',
      'banks.title': 'Bancos internacionales',
      'banks.suggested': 'Bancos internacionales sugeridos',
      'banks.go_n26': 'Ir a N26',
      'esims.popular': 'eSIM populares',
      'resource.insurance.subtitle': 'Compara opciones útiles de seguro.',
      'resource.youtoo.subtitle': 'Apoyo para Student Visa y estudios.',
      'resource.flights.subtitle': 'Partners útiles para reservar vuelos.',
      'resource.hostels.subtitle': 'Encuentra tus primeras noches.',
      'resource.banks.subtitle': 'Tarjetas y cuentas para la llegada.',
      'resource.esims.subtitle': 'Internet listo al aterrizar.',
      'donation.title': 'Apoya WorkyDay',
      'donation.body':
          'WorkyDay es gratis y está hecha para viajeros Working Holiday en Australia. Si te ayudó, puedes apoyar el proyecto.',
      'donation.button': 'Invítame a un café ☕',
      'profile.automatic_email': 'Edición automática de email',
      'profile.favourites': 'Favoritos',
      'profile.send_report': 'Enviar reporte',
      'profile.support': 'Invítame a un café',
      'profile.title': 'Perfil',
      'profile.settings': 'Ajustes del perfil',
      'profile.settings_body':
          'Configura el email automático, favoritos y herramientas.',
      'map.place_unknown': 'Lugar sin nombre',
      'map.google_paused': 'Google Maps está pausado temporalmente.',
      'map.dialog.profile': 'Perfil',
      'map.error.invalid_place': 'Este sitio no tiene un ID válido.',
      'map.worked.title': '¿Has trabajado aquí?',
      'map.worked.subtitle': 'Tu respuesta ayuda a otros usuarios.',
      'map.worked.no': 'No',
      'map.worked.already_title': 'Ya marcado',
      'map.worked.already_body': 'Este sitio ya está en tu lista de trabajos.',
      'map.worked.saved_local':
          'Guardado en este dispositivo. Se sincronizará más tarde.',
      'map.email.copy': 'Copiar email',
      'map.email.send': 'Enviar email',
      'map.email.copied': 'Email copiado',
      'map.location.denied':
          'Acceso a ubicación denegado. Toca de nuevo para permitirlo.',
      'map.location.services_off':
          'Los servicios de ubicación están desactivados.',
      'map.location.settings': 'Ajustes',
      'map.location.unavailable':
          'No pudimos obtener tu ubicación ahora mismo.',
      'map.location.blocked':
          'La ubicación está bloqueada. Abre ajustes y permite Ubicación.',
      'map.location.settings_failed':
          'No se pudieron abrir los ajustes de ubicación.',
      'map.tooltip.worked_here': 'He trabajado aquí',
      'map.tooltip.copy_phone': 'Copiar teléfono',
      'map.tooltip.email_options': 'Opciones de email',
      'map.tooltip.open_facebook': 'Abrir Facebook',
      'map.tooltip.view_jobs': 'Ver ofertas de trabajo',
      'map.tooltip.open_instagram': 'Abrir Instagram',
      'map.tooltip.add_favourite': 'Añadir a favoritos',
      'map.tooltip.remove_favourite': 'Quitar de favoritos',
      'map.tooltip.directions': 'Cómo llegar',
      'map.filter.title': 'Filtros',
      'map.filter.show_without_contact': 'Mostrar sitios sin web ni contacto',
      'favorites.empty': 'Aún no tienes favoritos',
      'favorites.load_error':
          'No pudimos cargar tus favoritos. Inténtalo de nuevo.',
      'review.title': '¿Te está gustando WorkyDay?',
      'review.body':
          'WorkyDay acaba de empezar. Valora la app y cuéntanos tu función favorita.',
      'review.not_now': 'Ahora no',
      'review.rate_app': 'Valorar app',
      'mail.save_message': 'Guardar mensaje',
      'mail.message_hint': 'Escribe aquí tu mensaje...',
      'mail.email_content': 'Contenido del email',
      'mail.upload_cv': 'Subir CV (PDF)',
      'mail.replace_cv': 'Reemplazar CV (PDF)',
      'mail.current_cv': 'CV actual',
      'mail.no_cv': 'ninguno',
      'forum.ask': 'Preguntar en el foro',
      'error.oops': 'Oops! ',
      'error.link_title': 'El enlace falló',
      'error.link_message': 'Este enlace no está disponible ahora.',
      'error.try_report': 'Inténtalo más tarde o repórtalo.',
      'error.load_title': 'No cargó',
      'error.load_message': 'Algo salió mal. Inténtalo de nuevo.',
      'error.email_title': 'Email fallido',
      'error.email_message': 'No pudimos abrir tu app de email.',
      'error.email_helper': 'Revisa Mail o repórtalo.',
      'onboarding.skip': 'Saltar',
      'onboarding.welcome.title': 'Bienvenido a WorkyDay 👋',
      'onboarding.welcome.description':
          'Encuentra trabajos e información útil para tu Working Holiday en Australia.\nHagamos un tour rápido.',
      'onboarding.welcome.primary': 'Empezar tour',
      'onboarding.map.title': 'Encuentra trabajos cerca',
      'onboarding.map.description':
          'Toca un lugar para ver detalles y contactar empleadores.',
      'onboarding.map.primary': 'Siguiente',
      'onboarding.automatic_email.title': 'Contacta más rápido',
      'onboarding.automatic_email.description':
          'Guarda tu mensaje y CV una vez para enviar solicitudes más rápido.',
      'onboarding.automatic_email.primary': 'Siguiente',
      'onboarding.guide.title': 'Guía de Australia',
      'onboarding.guide.description':
          'Todo lo que necesitas para tu Working Holiday:',
      'onboarding.guide.bullet.0': 'requisitos de visado',
      'onboarding.guide.bullet.1': 'trabajos',
      'onboarding.guide.bullet.2': 'alojamiento',
      'onboarding.guide.bullet.3': 'taxes y super',
      'onboarding.guide.primary': 'Siguiente',
      'onboarding.guide_kangaroo.title': 'Tu viaje por Australia',
      'onboarding.guide_kangaroo.description':
          'Toca el canguro para abrir la guía guiada y la checklist.',
      'onboarding.guide_kangaroo.primary': 'Finalizar',
    },
    'fr': {
      'common.close': 'Fermer',
      'common.clear': 'Effacer',
      'common.ok': 'OK',
      'common.yes': 'Oui',
      'common.retry': 'Réessayer',
      'common.try_again': 'Réessayer',
      'common.report_problem': 'Signaler un problème',
      'common.next_step': 'Prochaine étape',
      'common.what_can_you_do': 'Que faire ?',
      'common.copy_code': 'Copier le code',
      'common.discount_code': 'Code de réduction',
      'guide.title': 'Guide de l’Australie',
      'guide.search_hint': 'Rechercher',
      'guide.select_language': 'Choisir la langue',
      'guide.change_language': 'Changer de langue',
      'guide.no_results': 'Aucun résultat',
      'guide.no_sections': 'Aucune section trouvée.',
      'guide.load_error': 'Impossible de charger le guide.',
      'journey.title': 'Ton voyage en Australie',
      'journey.progress': 'Progression',
      'journey.checklist': 'Checklist Australie',
      'journey.open_full_guide': 'Ouvrir le guide complet',
      'journey.completed': 'Terminé',
      'journey.go_full_guide': 'Voir le guide complet',
      'journey.recommended_tools': 'Ressources recommandées',
      'journey.recommended': 'Recommandé',
      'journey.useful_resources': 'Ressources utiles',
      'journey.mark_completed': 'Marquer comme terminé',
      'journey.tasks_checked': 'tâches cochées',
      'journey.tasks_done': 'tâches faites',
      'journey.open': 'Ouvrir',
      'journey.done': 'Terminé',
      'journey.completed_title': 'Super ! Parcours terminé',
      'journey.completed_body':
          'Tu sais maintenant où trouver les sections importantes de WorkyDay.',
      'journey.message_completed':
          'Super ! Un pas de plus vers ton aventure Working Holiday.',
      'journey.message_start':
          'Salut ! Préparons ton arrivée en Australie 🇦🇺',
      'journey.mascot_checklist':
          'Utilise maintenant cette checklist pour l’Australie. Coche au fur et à mesure.',
      'journey.mascot_start': 'D’abord : visa, arrivée et bases essentielles.',
      'journey.step.visa_requirements.title': 'Visa et conditions',
      'journey.step.visa_requirements.description':
          'Découvre quel visa te convient avant de voyager.',
      'journey.step.visa_requirements.tip':
          'Commence ici. Tout dépend de ton type de visa.',
      'journey.step.visa_requirements.bullet.0': 'Comparer WHV et Student Visa',
      'journey.step.visa_requirements.bullet.1':
          'Vérifier âge, passeport et règles par pays',
      'journey.step.visa_requirements.bullet.2':
          'Préparer fonds, assurance et documents',
      'journey.step.visa_requirements.bullet.3':
          'Utiliser les sources officielles avant de postuler',
      'journey.step.before_arrival.title': 'Avant l’arrivée',
      'journey.step.before_arrival.description':
          'Prépare assurance, vols, argent et premier plan.',
      'journey.step.before_arrival.tip':
          'Un peu de préparation maintenant évite beaucoup de stress.',
      'journey.step.before_arrival.bullet.0':
          'Choisir première ville et saison',
      'journey.step.before_arrival.bullet.1':
          'Réserver vols et premières nuits',
      'journey.step.before_arrival.bullet.2':
          'Préparer argent, cartes et assurance',
      'journey.step.before_arrival.bullet.3': 'Prévoir internet dès l’arrivée',
      'journey.step.arrival_steps.title': 'Arrivée et démarches',
      'journey.step.arrival_steps.description':
          'Configure TFN, SIM et documents importants.',
      'journey.step.arrival_steps.tip':
          'Fais les démarches une fois, puis tout devient plus simple.',
      'journey.step.arrival_steps.bullet.0': 'Activer SIM ou eSIM',
      'journey.step.arrival_steps.bullet.1': 'Demander ton TFN correctement',
      'journey.step.arrival_steps.bullet.2':
          'Ouvrir un compte bancaire et garder les infos',
      'journey.step.arrival_steps.bullet.3':
          'Ranger certificats et documents importants',
      'journey.step.housing.title': 'Logement',
      'journey.step.housing.description':
          'Découvre où les backpackers logent souvent.',
      'journey.step.housing.tip':
          'Les premières nuits doivent être flexibles, sûres et bien situées.',
      'journey.step.housing.bullet.0': 'Commencer par hostel ou court séjour',
      'journey.step.housing.bullet.1': 'Comparer zone, transport et prix hebdo',
      'journey.step.housing.bullet.2': 'Éviter les dépôts trop rapides',
      'journey.step.housing.bullet.3':
          'Utiliser les groupes logement avec prudence',
      'journey.step.work.title': 'Jobs',
      'journey.step.work.description':
          'Apprends à trouver du travail et postuler.',
      'journey.step.work.tip':
          'Postule largement, relance vite et garde ton CV simple.',
      'journey.step.work.bullet.0': 'Préparer un CV style australien',
      'journey.step.work.bullet.1': 'Postuler en ligne et en personne',
      'journey.step.work.bullet.2': 'Relancer rapidement les managers',
      'journey.step.work.bullet.3': 'Suivre candidatures et contacts',
      'journey.step.regional_and_extension.title': 'Travail régional',
      'journey.step.regional_and_extension.description':
          'Comprends les jobs régionaux et bases du second visa.',
      'journey.step.regional_and_extension.tip':
          'Vérifie le postcode avant d’accepter un job.',
      'journey.step.regional_and_extension.bullet.0':
          'Vérifier si le postcode compte',
      'journey.step.regional_and_extension.bullet.1':
          'Comprendre industries et tâches éligibles',
      'journey.step.regional_and_extension.bullet.2':
          'Garder payslips et dates de travail',
      'journey.step.regional_and_extension.bullet.3':
          'Éviter les offres cash floues',
      'journey.step.transport.title': 'Véhicule',
      'journey.step.transport.description':
          'Acheter, louer ou voyager en Australie.',
      'journey.step.transport.tip':
          'Une voiture donne de la liberté, mais les papiers comptent.',
      'journey.step.transport.bullet.0': 'Comparer voiture, van, bus et vols',
      'journey.step.transport.bullet.1':
          'Vérifier rego, assurance et roadworthy',
      'journey.step.transport.bullet.2':
          'Prévoir carburant, réparations et péages',
      'journey.step.transport.bullet.3':
          'Planifier les longs trajets avec pauses',
      'journey.step.money_taxes.title': 'Salaires, impôts et super',
      'journey.step.money_taxes.description':
          'Comprends payslips, impôts et superannuation.',
      'journey.step.money_taxes.tip':
          'Connais ton taux horaire et garde chaque payslip.',
      'journey.step.money_taxes.bullet.0': 'Connaître ton salaire minimum',
      'journey.step.money_taxes.bullet.1':
          'Lire les payslips avant d’accepter un problème',
      'journey.step.money_taxes.bullet.2': 'Comprendre impôts et super',
      'journey.step.money_taxes.bullet.3':
          'Garder les preuves pour refunds et claims',
      'journey.step.visa_requirements.check.0': 'Choisir WHV ou Student Visa',
      'journey.step.visa_requirements.check.1':
          'Vérifier la validité du passeport',
      'journey.step.visa_requirements.check.2':
          'Vérifier les conditions de visa pour ton pays',
      'journey.step.visa_requirements.check.3':
          'Vérifier anglais/IELTS si nécessaire',
      'journey.step.visa_requirements.check.4':
          'Préparer assurance santé si requise',
      'journey.step.visa_requirements.check.5': 'Préparer preuve de fonds',
      'journey.step.visa_requirements.check.6':
          'Préparer documents d’études si nécessaire',
      'journey.step.visa_requirements.check.7':
          'Créer ou accéder à ImmiAccount',
      'journey.step.visa_requirements.check.8':
          'Sauvegarder les liens officiels immigration',
      'journey.step.before_arrival.check.0': 'Comparer les assurances voyage',
      'journey.step.before_arrival.check.1':
          'Réserver ton vol vers l’Australie',
      'journey.step.before_arrival.check.2': 'Réserver les premières nuits',
      'journey.step.before_arrival.check.3': 'Télécharger les cartes offline',
      'journey.step.before_arrival.check.4':
          'Préparer carte voyage ou banque de secours',
      'journey.step.before_arrival.check.5': 'Choisir eSIM ou SIM d’arrivée',
      'journey.step.before_arrival.check.6':
          'Sauvegarder documents importants offline',
      'journey.step.before_arrival.check.7':
          'Planifier transport aéroport-hostel',
      'journey.step.arrival_steps.check.0': 'Activer SIM ou eSIM',
      'journey.step.arrival_steps.check.1': 'Demander le TFN',
      'journey.step.arrival_steps.check.2':
          'Ouvrir ou préparer un compte bancaire',
      'journey.step.arrival_steps.check.3':
          'Configurer les infos superannuation',
      'journey.step.arrival_steps.check.4':
          'Préparer un numéro australien pour les formulaires',
      'journey.step.arrival_steps.check.5':
          'Sauvegarder copies passeport et visa',
      'journey.step.arrival_steps.check.6': 'Organiser certificats et IDs',
      'journey.step.arrival_steps.check.7': 'Sauvegarder contacts d’urgence',
      'journey.step.housing.check.0': 'Réserver hostel ou court séjour',
      'journey.step.housing.check.1': 'Rejoindre des groupes logement locaux',
      'journey.step.housing.check.2':
          'Vérifier transport avant de choisir une zone',
      'journey.step.housing.check.3': 'Préparer budget pour dépôt',
      'journey.step.housing.check.4': 'Éviter de payer avant vérification',
      'journey.step.housing.check.5': 'Visiter la chambre avant de s’engager',
      'journey.step.housing.check.6':
          'Confirmer factures et conditions du bond',
      'journey.step.housing.check.7': 'Garder une preuve écrite des paiements',
      'journey.step.work.check.0': 'Préparer un CV australien',
      'journey.step.work.check.1': 'Créer un suivi simple des jobs',
      'journey.step.work.check.2': 'Préparer un court message de présentation',
      'journey.step.work.check.3': 'Postuler en ligne',
      'journey.step.work.check.4': 'Distribuer des CVs en personne',
      'journey.step.work.check.5': 'Relancer les managers',
      'journey.step.work.check.6': 'Sauvegarder références et certificats',
      'journey.step.work.check.7': 'Vérifier le salaire avant d’accepter',
      'journey.step.regional_and_extension.check.0':
          'Vérifier le postcode éligible',
      'journey.step.regional_and_extension.check.1':
          'Confirmer industrie et tâche éligibles',
      'journey.step.regional_and_extension.check.2': 'Garder les payslips',
      'journey.step.regional_and_extension.check.3':
          'Suivre jours et infos employeur',
      'journey.step.regional_and_extension.check.4':
          'Garder timesheets signées si possible',
      'journey.step.regional_and_extension.check.5':
          'Confirmer ABN ou infos employeur',
      'journey.step.regional_and_extension.check.6':
          'Éviter les offres cash floues',
      'journey.step.regional_and_extension.check.7':
          'Sauvegarder preuves pour second visa',
      'journey.step.transport.check.0': 'Comparer options de transport',
      'journey.step.transport.check.1': 'Vérifier rego et assurance',
      'journey.step.transport.check.2': 'Inspecter le véhicule avant achat',
      'journey.step.transport.check.3': 'Vérifier PPSR/VIN avant achat',
      'journey.step.transport.check.4': 'Confirmer règles roadworthy par état',
      'journey.step.transport.check.5': 'Prévoir carburant et réparations',
      'journey.step.transport.check.6':
          'Préparer kit d’urgence et roue de secours',
      'journey.step.transport.check.7':
          'Planifier les longs trajets prudemment',
      'journey.step.money_taxes.check.0': 'Apprendre ton salaire minimum',
      'journey.step.money_taxes.check.1': 'Vérifier chaque payslip',
      'journey.step.money_taxes.check.2': 'Garder les documents fiscaux',
      'journey.step.money_taxes.check.3':
          'Confirmer que ton TFN est donné aux employeurs',
      'journey.step.money_taxes.check.4': 'Vérifier que la super est payée',
      'journey.step.money_taxes.check.5':
          'Sauvegarder tes infos superannuation',
      'journey.step.money_taxes.check.6':
          'Garder registres banque et employeur',
      'journey.step.money_taxes.check.7': 'Préparer la déclaration d’impôts',
      'kangaroo.bubble': 'Laisse-moi te guider en Australie 🇦🇺',
      'visa.types.title': 'Visa et conditions',
      'visa.types.heading': 'Types de visa',
      'visa.types.whv': 'Work and Holiday Visa',
      'visa.types.student': 'Student Visa',
      'visa.whv.b1': 'Voyager et travailler à temps plein',
      'visa.whv.b2': 'Changer librement d’employeur',
      'visa.whv.b3': 'Explorer l’Australie en économisant',
      'visa.whv.b4': 'Pour aventure et travail',
      'visa.whv.b5': 'Idéal pour un séjour court',
      'visa.student.b1': 'Étudier en école, TAFE ou université',
      'visa.student.b2': 'Travail à horaires limités',
      'visa.student.b3': 'Construire un avenir plus long',
      'visa.student.b4': 'Améliorer anglais ou compétences',
      'visa.student.b5': 'Idéal pour un projet d’études',
      'student.title': 'Student Visa',
      'student.what_title': 'Qu’est-ce qu’un Student Visa ?',
      'student.what_1':
          'Pour les personnes inscrites à un cours éligible en Australie.',
      'student.what_2':
          'Permet d’étudier dans des écoles, TAFE, universités ou centres approuvés.',
      'student.what_3':
          'Permet de travailler des heures limitées pendant les études.',
      'student.approval_title': 'Délai estimé',
      'student.approval_body':
          'Les délais varient selon le cours, le pays, les documents et la demande.',
      'student.requirements_title': 'Conditions Student Visa',
      'student.req_1': 'Passeport valide',
      'student.req_2': 'Confirmation of Enrolment d’un organisme approuvé',
      'student.req_3': 'Preuve de fonds pour cours, voyage et vie',
      'student.req_4': 'Assurance santé pour étudiants internationaux',
      'student.req_5': 'Niveau d’anglais ou documents si nécessaire',
      'student.important_title': 'Important',
      'student.important_body':
          'Les règles peuvent changer. Vérifie toujours le site officiel avant de postuler.',
      'student.apply_tab': 'Comment postuler',
      'student.requirements_tab': 'Conditions',
      'student.steps_title': 'Étapes de demande',
      'student.step_1': 'Choisis un cours et un organisme éligibles.',
      'student.step_2': 'Reçois ta Confirmation of Enrolment.',
      'student.step_3': 'Prépare documents, fonds et assurance santé.',
      'student.step_4': 'Postule en ligne via ImmiAccount.',
      'student.step_5': 'Attends la décision avant les plans finaux.',
      'student.balance_title': 'Équilibre travail/études',
      'student.balance_body':
          'Planifie ton budget autour des études. Les droits de travail sont limités.',
      'student.support_title': 'Aide Student Visa',
      'student.support_body':
          'Pour une aide visa ou écoles, nous recommandons YouTooProject.',
      'student.official_title': 'Information officielle',
      'student.official_button': 'Voir les détails Student Visa',
      'student.support_button': 'YouTooProject',
      'insurance.title': 'Assurance voyage',
      'insurance.recommended': 'Assurance recommandée',
      'insurance.compare': 'Comparer les assurances WHV',
      'flights.title': 'Vols',
      'flights.buy': 'Acheter tes vols',
      'hostels.where': 'Où réserver des hostels',
      'banks.title': 'Banques internationales',
      'banks.suggested': 'Banques internationales suggérées',
      'banks.go_n26': 'Aller sur N26',
      'esims.popular': 'eSIM populaires',
      'resource.insurance.subtitle': 'Compare des assurances utiles.',
      'resource.youtoo.subtitle': 'Aide pour visa étudiant et études.',
      'resource.flights.subtitle': 'Partenaires utiles pour les vols.',
      'resource.hostels.subtitle': 'Trouve tes premières nuits.',
      'resource.banks.subtitle': 'Cartes et comptes pour l’arrivée.',
      'resource.esims.subtitle': 'Internet prêt à l’atterrissage.',
      'donation.title': 'Soutenir WorkyDay',
      'donation.body':
          'WorkyDay est gratuite et créée pour les voyageurs Working Holiday en Australie. Si elle t’aide, tu peux soutenir le projet.',
      'donation.button': 'Offrir un café ☕',
      'profile.automatic_email': 'Email automatique',
      'profile.favourites': 'Favoris',
      'profile.send_report': 'Envoyer un signalement',
      'profile.support': 'Offrir un café',
      'profile.title': 'Profil',
      'profile.settings': 'Paramètres du profil',
      'profile.settings_body':
          'Configure l’email automatique, les favoris et les outils.',
      'map.place_unknown': 'Lieu sans nom',
      'map.google_paused': 'Google Maps est temporairement en pause.',
      'map.dialog.profile': 'Profil',
      'map.error.invalid_place': 'Ce lieu n’a pas d’ID valide.',
      'map.worked.title': 'Tu as travaillé ici ?',
      'map.worked.subtitle': 'Ta réponse aide les autres utilisateurs.',
      'map.worked.no': 'Non',
      'map.worked.already_title': 'Déjà marqué',
      'map.worked.already_body': 'Ce lieu est déjà dans ta liste de travail.',
      'map.worked.saved_local':
          'Enregistré sur cet appareil. La synchro pourra se faire plus tard.',
      'map.email.copy': 'Copier l’email',
      'map.email.send': 'Envoyer un email',
      'map.email.copied': 'Email copié',
      'map.location.denied':
          'Accès à la position refusé. Appuie encore pour l’autoriser.',
      'map.location.services_off':
          'Les services de localisation sont désactivés.',
      'map.location.settings': 'Réglages',
      'map.location.unavailable':
          'Impossible d’obtenir ta position pour le moment.',
      'map.location.blocked':
          'La localisation est bloquée. Ouvre les réglages et autorise Position.',
      'map.location.settings_failed':
          'Impossible d’ouvrir les réglages de localisation.',
      'map.tooltip.worked_here': 'J’ai travaillé ici',
      'map.tooltip.copy_phone': 'Copier le téléphone',
      'map.tooltip.email_options': 'Options email',
      'map.tooltip.open_facebook': 'Ouvrir Facebook',
      'map.tooltip.view_jobs': 'Voir les offres',
      'map.tooltip.open_instagram': 'Ouvrir Instagram',
      'map.tooltip.add_favourite': 'Ajouter aux favoris',
      'map.tooltip.remove_favourite': 'Retirer des favoris',
      'map.tooltip.directions': 'Itinéraire',
      'map.filter.title': 'Filtres',
      'map.filter.show_without_contact':
          'Afficher les lieux sans site ni contact',
      'favorites.empty': 'Aucun favori pour le moment',
      'favorites.load_error': 'Impossible de charger tes favoris. Réessaie.',
      'review.title': 'Tu apprécies WorkyDay ?',
      'review.body':
          'WorkyDay démarre à peine. Note l’app et dis-nous ta fonctionnalité préférée.',
      'review.not_now': 'Pas maintenant',
      'review.rate_app': 'Noter l’app',
      'mail.save_message': 'Enregistrer le message',
      'mail.message_hint': 'Écris ton message ici...',
      'mail.email_content': 'Contenu de l’email',
      'mail.upload_cv': 'Importer le CV (PDF)',
      'mail.replace_cv': 'Remplacer le CV (PDF)',
      'mail.current_cv': 'CV actuel',
      'mail.no_cv': 'aucun',
      'forum.ask': 'Demander au forum',
      'error.oops': 'Oops! ',
      'error.link_title': 'Lien indisponible',
      'error.link_message': 'Ce lien n’est pas disponible pour le moment.',
      'error.try_report': 'Réessaie plus tard ou signale-le.',
      'error.load_title': 'Chargement impossible',
      'error.load_message': 'Un problème est survenu. Réessaie.',
      'error.email_title': 'Email impossible',
      'error.email_message': 'Impossible d’ouvrir ton app email.',
      'error.email_helper': 'Vérifie Mail ou signale-le.',
      'onboarding.skip': 'Passer',
      'onboarding.welcome.title': 'Bienvenue sur WorkyDay 👋',
      'onboarding.welcome.description':
          'Trouve des jobs et infos utiles pour ton Working Holiday en Australie.\nFaisons un tour rapide.',
      'onboarding.welcome.primary': 'Commencer',
      'onboarding.map.title': 'Trouve des lieux de travail',
      'onboarding.map.description':
          'Touche un lieu pour voir les détails et contacter les employeurs.',
      'onboarding.map.primary': 'Suivant',
      'onboarding.automatic_email.title': 'Contacte plus vite',
      'onboarding.automatic_email.description':
          'Enregistre ton message et CV une fois pour postuler plus vite.',
      'onboarding.automatic_email.primary': 'Suivant',
      'onboarding.guide.title': 'Guide de l’Australie',
      'onboarding.guide.description':
          'Tout ce qu’il faut pour ton Working Holiday :',
      'onboarding.guide.bullet.0': 'conditions de visa',
      'onboarding.guide.bullet.1': 'jobs',
      'onboarding.guide.bullet.2': 'logement',
      'onboarding.guide.bullet.3': 'impôts et super',
      'onboarding.guide.primary': 'Suivant',
      'onboarding.guide_kangaroo.title': 'Ton voyage en Australie',
      'onboarding.guide_kangaroo.description':
          'Touche le kangourou pour ouvrir le parcours guidé et la checklist.',
      'onboarding.guide_kangaroo.primary': 'Terminer',
    },
    'de': {
      'common.close': 'Schließen',
      'common.clear': 'Löschen',
      'common.ok': 'OK',
      'common.yes': 'Ja',
      'common.retry': 'Erneut versuchen',
      'common.try_again': 'Erneut versuchen',
      'common.report_problem': 'Problem melden',
      'common.next_step': 'Nächster Schritt',
      'common.what_can_you_do': 'Was kannst du tun?',
      'common.copy_code': 'Code kopieren',
      'common.discount_code': 'Rabattcode',
      'guide.title': 'Australien-Guide',
      'guide.search_hint': 'Suchen',
      'guide.select_language': 'Sprache wählen',
      'guide.change_language': 'Sprache ändern',
      'guide.no_results': 'Keine Ergebnisse',
      'guide.no_sections': 'Keine Bereiche gefunden.',
      'guide.load_error': 'Der Guide konnte nicht geladen werden.',
      'journey.title': 'Deine Australien-Reise',
      'journey.progress': 'Reisefortschritt',
      'journey.checklist': 'Australien-Checkliste',
      'journey.open_full_guide': 'Vollständigen Guide öffnen',
      'journey.completed': 'Erledigt',
      'journey.go_full_guide': 'Zum vollständigen Guide',
      'journey.recommended_tools': 'Empfohlene Ressourcen',
      'journey.recommended': 'Empfohlen',
      'journey.useful_resources': 'Nützliche Ressourcen',
      'journey.mark_completed': 'Als erledigt markieren',
      'journey.tasks_checked': 'Aufgaben abgehakt',
      'journey.tasks_done': 'Aufgaben erledigt',
      'journey.open': 'Öffnen',
      'journey.done': 'Fertig',
      'journey.completed_title': 'Super! Reise abgeschlossen',
      'journey.completed_body':
          'Du weißt jetzt, wo die wichtigen WorkyDay-Guide-Bereiche sind.',
      'journey.message_completed':
          'Sehr gut! Ein Schritt näher an deinem Working-Holiday-Abenteuer.',
      'journey.message_start':
          'Hey! Machen wir dich bereit für Australien 🇦🇺',
      'journey.mascot_checklist':
          'Nutze dies jetzt als Australien-Checkliste. Hake alles unterwegs ab.',
      'journey.mascot_start':
          'Zuerst: Visum, Ankunft und grundlegende Einrichtung.',
      'journey.step.visa_requirements.title': 'Visum & Voraussetzungen',
      'journey.step.visa_requirements.description':
          'Finde heraus, welches Visum vor der Reise passt.',
      'journey.step.visa_requirements.tip':
          'Starte hier. Alles hängt von deinem Visum ab.',
      'journey.step.visa_requirements.bullet.0':
          'WHV und Student Visa vergleichen',
      'journey.step.visa_requirements.bullet.1':
          'Alter, Reisepass und Länderregeln prüfen',
      'journey.step.visa_requirements.bullet.2':
          'Geld, Versicherung und Dokumente prüfen',
      'journey.step.visa_requirements.bullet.3':
          'Vor dem Antrag offizielle Quellen nutzen',
      'journey.step.before_arrival.title': 'Vor der Ankunft',
      'journey.step.before_arrival.description':
          'Bereite Versicherung, Flüge, Geld und ersten Plan vor.',
      'journey.step.before_arrival.tip':
          'Etwas Vorbereitung spart später viel Stress.',
      'journey.step.before_arrival.bullet.0': 'Erste Stadt und Saison planen',
      'journey.step.before_arrival.bullet.1': 'Flüge und erste Nächte buchen',
      'journey.step.before_arrival.bullet.2':
          'Geld, Karten und Versicherung vorbereiten',
      'journey.step.before_arrival.bullet.3':
          'Internet für die Landung einrichten',
      'journey.step.arrival_steps.title': 'Ankunft & Papierkram',
      'journey.step.arrival_steps.description':
          'Richte TFN, SIM und wichtige Dokumente ein.',
      'journey.step.arrival_steps.tip':
          'Mach den Papierkram einmal, dann wird Australien einfacher.',
      'journey.step.arrival_steps.bullet.0': 'SIM oder eSIM aktivieren',
      'journey.step.arrival_steps.bullet.1': 'TFN korrekt beantragen',
      'journey.step.arrival_steps.bullet.2':
          'Bankkonto öffnen und Daten sichern',
      'journey.step.arrival_steps.bullet.3':
          'Zertifikate und wichtige Dokumente speichern',
      'journey.step.housing.title': 'Unterkunft',
      'journey.step.housing.description':
          'Erfahre, wo Backpacker meist wohnen.',
      'journey.step.housing.tip':
          'Am Anfang zählen Lage, Flexibilität und Sicherheit.',
      'journey.step.housing.bullet.0': 'Mit Hostel oder Kurzaufenthalt starten',
      'journey.step.housing.bullet.1':
          'Lage, Transport und Wochenpreis vergleichen',
      'journey.step.housing.bullet.2': 'Kautionen nicht zu schnell senden',
      'journey.step.housing.bullet.3': 'Wohnungsgruppen vorsichtig nutzen',
      'journey.step.work.title': 'Jobs',
      'journey.step.work.description':
          'Lerne, wie du Arbeit findest und dich bewirbst.',
      'journey.step.work.tip':
          'Breit bewerben, schnell nachfassen und CV einfach halten.',
      'journey.step.work.bullet.0': 'Einfachen australischen CV vorbereiten',
      'journey.step.work.bullet.1': 'Online und persönlich bewerben',
      'journey.step.work.bullet.2': 'Schnell bei Managern nachfassen',
      'journey.step.work.bullet.3': 'Bewerbungen und Kontakte verfolgen',
      'journey.step.regional_and_extension.title': 'Regionalarbeit',
      'journey.step.regional_and_extension.description':
          'Verstehe regionale Jobs und Grundlagen fürs zweite Visum.',
      'journey.step.regional_and_extension.tip':
          'Prüfe die Postleitzahl, bevor du einen Job annimmst.',
      'journey.step.regional_and_extension.bullet.0':
          'Prüfen, ob die Postleitzahl zählt',
      'journey.step.regional_and_extension.bullet.1':
          'Geeignete Branchen und Aufgaben verstehen',
      'journey.step.regional_and_extension.bullet.2':
          'Payslips und Arbeitstage speichern',
      'journey.step.regional_and_extension.bullet.3':
          'Unklare Cash-Angebote vermeiden',
      'journey.step.transport.title': 'Fahrzeug',
      'journey.step.transport.description':
          'Kaufen, mieten oder durch Australien reisen.',
      'journey.step.transport.tip':
          'Ein Auto bringt Freiheit, aber Papierkram zählt.',
      'journey.step.transport.bullet.0': 'Auto, Van, Bus und Flüge vergleichen',
      'journey.step.transport.bullet.1':
          'Rego, Versicherung und Roadworthy prüfen',
      'journey.step.transport.bullet.2':
          'Sprit, Reparaturen und Maut einplanen',
      'journey.step.transport.bullet.3': 'Lange Fahrten mit Pausen planen',
      'journey.step.money_taxes.title': 'Lohn, Steuern & Super',
      'journey.step.money_taxes.description':
          'Verstehe Payslips, Steuern und Superannuation.',
      'journey.step.money_taxes.tip':
          'Kenne deinen Lohnsatz und behalte jede Payslip.',
      'journey.step.money_taxes.bullet.0': 'Mindestlohn kennen',
      'journey.step.money_taxes.bullet.1': 'Payslips bei Problemen genau lesen',
      'journey.step.money_taxes.bullet.2':
          'Steuern und Super-Grundlagen verstehen',
      'journey.step.money_taxes.bullet.3':
          'Unterlagen für Refunds und Claims behalten',
      'journey.step.visa_requirements.check.0': 'WHV oder Student Visa wählen',
      'journey.step.visa_requirements.check.1': 'Reisepassgültigkeit prüfen',
      'journey.step.visa_requirements.check.2':
          'Visumsvoraussetzungen für dein Land prüfen',
      'journey.step.visa_requirements.check.3':
          'Englisch/IELTS prüfen, falls nötig',
      'journey.step.visa_requirements.check.4':
          'Krankenversicherung vorbereiten, falls nötig',
      'journey.step.visa_requirements.check.5': 'Finanznachweis vorbereiten',
      'journey.step.visa_requirements.check.6':
          'Bildungsdokumente vorbereiten, falls nötig',
      'journey.step.visa_requirements.check.7':
          'ImmiAccount erstellen oder öffnen',
      'journey.step.visa_requirements.check.8':
          'Offizielle Immigration-Links speichern',
      'journey.step.before_arrival.check.0': 'Reiseversicherungen vergleichen',
      'journey.step.before_arrival.check.1': 'Flug nach Australien buchen',
      'journey.step.before_arrival.check.2': 'Erste Nächte buchen',
      'journey.step.before_arrival.check.3': 'Offline-Karten für Ankunft laden',
      'journey.step.before_arrival.check.4':
          'Reisekarte oder Bank-Backup vorbereiten',
      'journey.step.before_arrival.check.5': 'eSIM oder Ankunfts-SIM wählen',
      'journey.step.before_arrival.check.6':
          'Wichtige Dokumente offline speichern',
      'journey.step.before_arrival.check.7':
          'Transport Flughafen-Hostel planen',
      'journey.step.arrival_steps.check.0': 'SIM oder eSIM aktivieren',
      'journey.step.arrival_steps.check.1': 'TFN beantragen',
      'journey.step.arrival_steps.check.2': 'Bankkonto öffnen oder vorbereiten',
      'journey.step.arrival_steps.check.3': 'Super-Kontodaten einrichten',
      'journey.step.arrival_steps.check.4':
          'Australische Nummer für Formulare bereithalten',
      'journey.step.arrival_steps.check.5': 'Pass- und Visakopien speichern',
      'journey.step.arrival_steps.check.6': 'Zertifikate und IDs organisieren',
      'journey.step.arrival_steps.check.7': 'Notfallkontakte speichern',
      'journey.step.housing.check.0': 'Hostel oder Kurzaufenthalt buchen',
      'journey.step.housing.check.1': 'Lokalen Wohnungsgruppen beitreten',
      'journey.step.housing.check.2': 'Transport vor Gebietswahl prüfen',
      'journey.step.housing.check.3': 'Kautionsbudget vorbereiten',
      'journey.step.housing.check.4': 'Nicht zahlen, bevor Ort geprüft ist',
      'journey.step.housing.check.5': 'Zimmer vor Zusage besichtigen',
      'journey.step.housing.check.6': 'Rechnungen und Bond-Bedingungen klären',
      'journey.step.housing.check.7': 'Schriftliche Zahlungsbelege behalten',
      'journey.step.work.check.0': 'Australischen CV vorbereiten',
      'journey.step.work.check.1': 'Einfachen Job-Tracker erstellen',
      'journey.step.work.check.2': 'Kurze Bewerbungsnachricht vorbereiten',
      'journey.step.work.check.3': 'Online bewerben',
      'journey.step.work.check.4': 'CVs persönlich abgeben',
      'journey.step.work.check.5': 'Bei Managern nachfassen',
      'journey.step.work.check.6': 'Referenzen und Zertifikate speichern',
      'journey.step.work.check.7': 'Lohnsatz vor Annahme prüfen',
      'journey.step.regional_and_extension.check.0':
          'Geeignete Postleitzahl prüfen',
      'journey.step.regional_and_extension.check.1':
          'Geeignete Branche und Aufgabe bestätigen',
      'journey.step.regional_and_extension.check.2': 'Payslips speichern',
      'journey.step.regional_and_extension.check.3':
          'Tage und Arbeitgeberdaten verfolgen',
      'journey.step.regional_and_extension.check.4':
          'Signierte Timesheets behalten, wenn möglich',
      'journey.step.regional_and_extension.check.5':
          'ABN oder Arbeitgeberdaten bestätigen',
      'journey.step.regional_and_extension.check.6':
          'Unklare Cash-only-Angebote vermeiden',
      'journey.step.regional_and_extension.check.7':
          'Nachweise fürs zweite Visum sichern',
      'journey.step.transport.check.0': 'Transportoptionen vergleichen',
      'journey.step.transport.check.1': 'Rego und Versicherung prüfen',
      'journey.step.transport.check.2': 'Fahrzeug vor Kauf prüfen',
      'journey.step.transport.check.3': 'PPSR/VIN vor Kauf prüfen',
      'journey.step.transport.check.4': 'Roadworthy-Regeln je Staat prüfen',
      'journey.step.transport.check.5': 'Sprit und Reparaturen einplanen',
      'journey.step.transport.check.6':
          'Notfallset und Ersatzreifen vorbereiten',
      'journey.step.transport.check.7': 'Lange Fahrten sicher planen',
      'journey.step.money_taxes.check.0': 'Mindestlohn lernen',
      'journey.step.money_taxes.check.1': 'Jede Payslip prüfen',
      'journey.step.money_taxes.check.2': 'Steuerunterlagen behalten',
      'journey.step.money_taxes.check.3':
          'Bestätigen, dass Arbeitgeber deine TFN haben',
      'journey.step.money_taxes.check.4': 'Prüfen, ob Super bezahlt wird',
      'journey.step.money_taxes.check.5': 'Superannuation-Daten speichern',
      'journey.step.money_taxes.check.6': 'Bank- und Arbeitgeberdaten behalten',
      'journey.step.money_taxes.check.7': 'Auf Steuererklärung vorbereiten',
      'kangaroo.bubble': 'Lass mich dich durch Australien führen 🇦🇺',
      'visa.types.title': 'Visum & Voraussetzungen',
      'visa.types.heading': 'Visa-Arten',
      'visa.types.whv': 'Work and Holiday Visa',
      'visa.types.student': 'Student Visa',
      'visa.whv.b1': 'Reisen und Vollzeit arbeiten',
      'visa.whv.b2': 'Arbeitgeber frei wechseln',
      'visa.whv.b3': 'Australien entdecken und sparen',
      'visa.whv.b4': 'Für Abenteuer und Arbeit',
      'visa.whv.b5': 'Gut für kurzfristige Pläne',
      'visa.student.b1': 'An Schule, TAFE oder Uni studieren',
      'visa.student.b2': 'Begrenzt arbeiten',
      'visa.student.b3': 'Langfristige Zukunft aufbauen',
      'visa.student.b4': 'Englisch oder Skills verbessern',
      'visa.student.b5': 'Ideal für Studienpläne',
      'student.title': 'Student Visa',
      'student.what_title': 'Was ist ein Student Visa?',
      'student.what_1':
          'Für Personen, die in Australien in einem geeigneten Kurs eingeschrieben sind.',
      'student.what_2':
          'Erlaubt Studium an Schulen, TAFE, Unis oder anerkannten Anbietern.',
      'student.what_3':
          'Erlaubt begrenzte Arbeitsstunden während des Studiums.',
      'student.approval_title': 'Geschätzte Bearbeitungszeit',
      'student.approval_body':
          'Die Zeiten hängen von Kurs, Land, Dokumenten und Antrag ab.',
      'student.requirements_title': 'Student-Visa-Voraussetzungen',
      'student.req_1': 'Gültiger Reisepass',
      'student.req_2': 'Confirmation of Enrolment eines anerkannten Anbieters',
      'student.req_3':
          'Finanznachweis für Kurs, Reise und Lebenshaltungskosten',
      'student.req_4': 'Krankenversicherung für internationale Studierende',
      'student.req_5': 'Englischnachweis oder Bildungsdokumente falls nötig',
      'student.important_title': 'Wichtig',
      'student.important_body':
          'Regeln können sich ändern. Prüfe vor dem Antrag immer die offizielle Website.',
      'student.apply_tab': 'So beantragst du es',
      'student.requirements_tab': 'Voraussetzungen',
      'student.steps_title': 'Antragsschritte',
      'student.step_1': 'Wähle einen geeigneten Kurs und Anbieter.',
      'student.step_2': 'Erhalte deine Confirmation of Enrolment.',
      'student.step_3':
          'Bereite Dokumente, Finanznachweise und Versicherung vor.',
      'student.step_4': 'Beantrage online über ImmiAccount.',
      'student.step_5': 'Warte die Entscheidung ab, bevor du final planst.',
      'student.balance_title': 'Arbeit und Studium',
      'student.balance_body':
          'Plane dein Budget zuerst rund ums Studium. Arbeitsrechte sind begrenzt.',
      'student.support_title': 'Student-Visa-Hilfe',
      'student.support_body':
          'Für Hilfe mit Visum oder Schulen empfehlen wir YouTooProject.',
      'student.official_title': 'Offizielle Informationen',
      'student.official_button': 'Student-Visa-Details ansehen',
      'student.support_button': 'YouTooProject',
      'insurance.title': 'Reiseversicherung',
      'insurance.recommended': 'Empfohlene Versicherung',
      'insurance.compare': 'WHV-Versicherung vergleichen',
      'flights.title': 'Flüge',
      'flights.buy': 'Flüge buchen',
      'hostels.where': 'Hostels buchen',
      'banks.title': 'Internationale Banken',
      'banks.suggested': 'Empfohlene internationale Banken',
      'banks.go_n26': 'Zu N26',
      'esims.popular': 'Beliebte eSIMs',
      'resource.insurance.subtitle': 'Vergleiche nützliche Versicherungen.',
      'resource.youtoo.subtitle': 'Hilfe für Studentenvisum und Studium.',
      'resource.flights.subtitle': 'Nützliche Partner für Flüge.',
      'resource.hostels.subtitle': 'Finde deine ersten Nächte.',
      'resource.banks.subtitle': 'Karten und Konten für die Ankunft.',
      'resource.esims.subtitle': 'Internet direkt nach der Landung.',
      'donation.title': 'WorkyDay unterstützen',
      'donation.body':
          'WorkyDay ist kostenlos und für Working-Holiday-Reisende in Australien gebaut. Wenn es hilft, kannst du das Projekt unterstützen.',
      'donation.button': 'Kaffee spendieren ☕',
      'profile.automatic_email': 'Automatische E-Mail',
      'profile.favourites': 'Favoriten',
      'profile.send_report': 'Meldung senden',
      'profile.support': 'Kaffee spendieren',
      'profile.title': 'Profil',
      'profile.settings': 'Profileinstellungen',
      'profile.settings_body':
          'Richte automatische E-Mail, Favoriten und App-Tools ein.',
      'map.place_unknown': 'Unbenannter Ort',
      'map.google_paused': 'Google Maps ist vorübergehend pausiert.',
      'map.dialog.profile': 'Profil',
      'map.error.invalid_place': 'Dieser Ort hat keine gültige ID.',
      'map.worked.title': 'Hast du hier gearbeitet?',
      'map.worked.subtitle': 'Dein Feedback hilft anderen Nutzern.',
      'map.worked.no': 'Nein',
      'map.worked.already_title': 'Schon markiert',
      'map.worked.already_body':
          'Dieser Ort ist bereits in deiner Arbeitsliste.',
      'map.worked.saved_local':
          'Auf diesem Gerät gespeichert. Synchronisierung später möglich.',
      'map.email.copy': 'E-Mail kopieren',
      'map.email.send': 'E-Mail senden',
      'map.email.copied': 'E-Mail kopiert',
      'map.location.denied':
          'Standortzugriff verweigert. Tippe erneut, um ihn zu erlauben.',
      'map.location.services_off': 'Standortdienste sind deaktiviert.',
      'map.location.settings': 'Einstellungen',
      'map.location.unavailable':
          'Dein Standort konnte gerade nicht abgerufen werden.',
      'map.location.blocked':
          'Standortzugriff ist blockiert. Öffne Einstellungen und erlaube Standort.',
      'map.location.settings_failed':
          'Standorteinstellungen konnten nicht geöffnet werden.',
      'map.tooltip.worked_here': 'Ich habe hier gearbeitet',
      'map.tooltip.copy_phone': 'Telefon kopieren',
      'map.tooltip.email_options': 'E-Mail-Optionen',
      'map.tooltip.open_facebook': 'Facebook öffnen',
      'map.tooltip.view_jobs': 'Jobangebote ansehen',
      'map.tooltip.open_instagram': 'Instagram öffnen',
      'map.tooltip.add_favourite': 'Zu Favoriten hinzufügen',
      'map.tooltip.remove_favourite': 'Aus Favoriten entfernen',
      'map.tooltip.directions': 'Route',
      'map.filter.title': 'Filter',
      'map.filter.show_without_contact':
          'Orte ohne Website oder Kontakt anzeigen',
      'favorites.empty': 'Noch keine Favoriten',
      'favorites.load_error':
          'Favoriten konnten nicht geladen werden. Versuche es erneut.',
      'review.title': 'Gefällt dir WorkyDay?',
      'review.body':
          'WorkyDay steht noch am Anfang. Bewerte die App und sag uns, was dir am besten gefällt.',
      'review.not_now': 'Nicht jetzt',
      'review.rate_app': 'App bewerten',
      'mail.save_message': 'Nachricht speichern',
      'mail.message_hint': 'Schreib hier deine Nachricht...',
      'mail.email_content': 'E-Mail-Inhalt',
      'mail.upload_cv': 'Lebenslauf hochladen (PDF)',
      'mail.replace_cv': 'Lebenslauf ersetzen (PDF)',
      'mail.current_cv': 'Aktueller Lebenslauf',
      'mail.no_cv': 'keiner',
      'forum.ask': 'Im Forum fragen',
      'error.oops': 'Oops! ',
      'error.link_title': 'Link fehlgeschlagen',
      'error.link_message': 'Dieser Link ist gerade nicht verfügbar.',
      'error.try_report': 'Versuche es später erneut oder melde es.',
      'error.load_title': 'Nicht geladen',
      'error.load_message': 'Etwas ist schiefgelaufen. Versuche es erneut.',
      'error.email_title': 'E-Mail fehlgeschlagen',
      'error.email_message': 'Deine E-Mail-App konnte nicht geöffnet werden.',
      'error.email_helper': 'Prüfe Mail oder melde es.',
      'onboarding.skip': 'Überspringen',
      'onboarding.welcome.title': 'Willkommen bei WorkyDay 👋',
      'onboarding.welcome.description':
          'Finde Jobs und nützliche Infos für dein Working Holiday in Australien.\nMachen wir eine kurze Tour.',
      'onboarding.welcome.primary': 'Tour starten',
      'onboarding.map.title': 'Arbeitsplätze in deiner Nähe',
      'onboarding.map.description':
          'Tippe auf einen Ort, um Details zu sehen und Arbeitgeber zu kontaktieren.',
      'onboarding.map.primary': 'Weiter',
      'onboarding.automatic_email.title': 'Arbeitgeber schneller kontaktieren',
      'onboarding.automatic_email.description':
          'Speichere Nachricht und Lebenslauf einmal und bewirb dich schneller.',
      'onboarding.automatic_email.primary': 'Weiter',
      'onboarding.guide.title': 'Australien-Guide',
      'onboarding.guide.description':
          'Alles, was du für dein Working Holiday brauchst:',
      'onboarding.guide.bullet.0': 'Visa-Voraussetzungen',
      'onboarding.guide.bullet.1': 'Jobs',
      'onboarding.guide.bullet.2': 'Unterkunft',
      'onboarding.guide.bullet.3': 'Steuern und Super',
      'onboarding.guide.primary': 'Weiter',
      'onboarding.guide_kangaroo.title': 'Deine Australien-Reise',
      'onboarding.guide_kangaroo.description':
          'Tippe auf das Känguru, um den geführten Weg und die Checkliste zu öffnen.',
      'onboarding.guide_kangaroo.primary': 'Fertig',
    },
    'hi': {
      'common.close': 'बंद करें',
      'common.clear': 'साफ़ करें',
      'common.ok': 'OK',
      'common.yes': 'हाँ',
      'common.retry': 'फिर कोशिश करें',
      'common.try_again': 'फिर कोशिश करें',
      'common.report_problem': 'समस्या रिपोर्ट करें',
      'common.next_step': 'अगला कदम',
      'common.what_can_you_do': 'आप क्या कर सकते हैं?',
      'common.copy_code': 'कोड कॉपी करें',
      'common.discount_code': 'डिस्काउंट कोड',
      'guide.title': 'ऑस्ट्रेलिया गाइड',
      'guide.search_hint': 'कुछ भी खोजें',
      'guide.select_language': 'भाषा चुनें',
      'guide.change_language': 'भाषा बदलें',
      'guide.no_results': 'कोई परिणाम नहीं मिला',
      'guide.no_sections': 'कोई सेक्शन नहीं मिला।',
      'guide.load_error': 'गाइड लोड नहीं हो सकी।',
      'journey.title': 'आपकी ऑस्ट्रेलिया यात्रा',
      'journey.progress': 'यात्रा प्रगति',
      'journey.checklist': 'ऑस्ट्रेलिया चेकलिस्ट',
      'journey.open_full_guide': 'पूरी गाइड खोलें',
      'journey.completed': 'पूरा',
      'journey.go_full_guide': 'पूरी गाइड पर जाएं',
      'journey.recommended_tools': 'अनुशंसित संसाधन',
      'journey.recommended': 'अनुशंसित',
      'journey.useful_resources': 'उपयोगी संसाधन',
      'journey.mark_completed': 'पूरा मार्क करें',
      'journey.tasks_checked': 'कार्य चुने गए',
      'journey.tasks_done': 'कार्य पूरे',
      'journey.open': 'खोलें',
      'journey.done': 'हो गया',
      'journey.completed_title': 'बढ़िया! यात्रा पूरी हुई',
      'journey.completed_body':
          'अब आपको WorkyDay guide के important sections पता हैं.',
      'journey.message_completed':
          'Nice! Your Working Holiday adventure is closer.',
      'journey.message_start': 'Hey mate! Australia के लिए तैयार हो जाएं 🇦🇺',
      'journey.mascot_checklist': 'अब इसे Australia checklist की तरह use करें.',
      'journey.mascot_start': 'पहले: visa, arrival और basic setup.',
      'journey.step.visa_requirements.title': 'वीज़ा और आवश्यकताएँ',
      'journey.step.visa_requirements.description':
          'Travel से पहले सही visa path समझें.',
      'journey.step.visa_requirements.tip':
          'यहीं से शुरू करें. बाकी सब visa path पर निर्भर है.',
      'journey.step.visa_requirements.bullet.0':
          'WHV और Student Visa compare करें',
      'journey.step.visa_requirements.bullet.1':
          'Age, passport और country rules check करें',
      'journey.step.visa_requirements.bullet.2':
          'Funds, insurance और documents review करें',
      'journey.step.visa_requirements.bullet.3':
          'Apply से पहले official sources देखें',
      'journey.step.before_arrival.title': 'Arrival से पहले',
      'journey.step.before_arrival.description':
          'Insurance, flights, money और first plan prepare करें.',
      'journey.step.before_arrival.tip':
          'थोड़ी तैयारी बाद में बहुत stress बचाती है.',
      'journey.step.before_arrival.bullet.0': 'First city और season plan करें',
      'journey.step.before_arrival.bullet.1':
          'Flights और first nights book करें',
      'journey.step.before_arrival.bullet.2':
          'Money, cards और travel cover prepare करें',
      'journey.step.before_arrival.bullet.3': 'Landing पर internet ready रखें',
      'journey.step.arrival_steps.title': 'आगमन और कागज़ात',
      'journey.step.arrival_steps.description':
          'TFN, SIM और key documents set up करें.',
      'journey.step.arrival_steps.tip':
          'Setup एक बार कर लें, फिर Australia आसान लगेगा.',
      'journey.step.arrival_steps.bullet.0': 'SIM या eSIM activate करें',
      'journey.step.arrival_steps.bullet.1': 'TFN सही तरीके से apply करें',
      'journey.step.arrival_steps.bullet.2':
          'Bank account खोलें और details safe रखें',
      'journey.step.arrival_steps.bullet.3':
          'Certificates और important paperwork save करें',
      'journey.step.housing.title': 'रहना',
      'journey.step.housing.description':
          'Backpackers आमतौर पर कहाँ रहते हैं, समझें.',
      'journey.step.housing.tip':
          'First nights में location, flexibility और safety important हैं.',
      'journey.step.housing.bullet.0': 'Hostels या short stays से start करें',
      'journey.step.housing.bullet.1':
          'Location, transport और weekly price compare करें',
      'journey.step.housing.bullet.2': 'Deposit बहुत जल्दी न भेजें',
      'journey.step.housing.bullet.3': 'Housing groups सावधानी से use करें',
      'journey.step.work.title': 'नौकरियाँ',
      'journey.step.work.description':
          'काम कैसे ढूंढना और apply करना है, सीखें.',
      'journey.step.work.tip':
          'ज्यादा apply करें, जल्दी follow up करें और CV simple रखें.',
      'journey.step.work.bullet.0': 'Simple Australian-style CV prepare करें',
      'journey.step.work.bullet.1': 'Online और in person apply करें',
      'journey.step.work.bullet.2': 'Managers को जल्दी follow up करें',
      'journey.step.work.bullet.3': 'Applications और contacts track करें',
      'journey.step.regional_and_extension.title': 'रीजनल फार्म काम',
      'journey.step.regional_and_extension.description':
          'Regional jobs और second-year visa basics समझें.',
      'journey.step.regional_and_extension.tip':
          'Job accept करने से पहले postcode eligibility check करें.',
      'journey.step.regional_and_extension.bullet.0':
          'Postcode eligible है या नहीं check करें',
      'journey.step.regional_and_extension.bullet.1':
          'Eligible industries और tasks समझें',
      'journey.step.regional_and_extension.bullet.2':
          'Payslips और work dates track करें',
      'journey.step.regional_and_extension.bullet.3':
          'Unclear cash-in-hand offers avoid करें',
      'journey.step.transport.title': 'वाहन',
      'journey.step.transport.description':
          'Australia में buying, renting या travelling.',
      'journey.step.transport.tip':
          'Car freedom देती है, लेकिन paperwork important है.',
      'journey.step.transport.bullet.0':
          'Car, van, bus और flights compare करें',
      'journey.step.transport.bullet.1':
          'Rego, insurance और roadworthy rules check करें',
      'journey.step.transport.bullet.2': 'Fuel, repairs और tolls budget करें',
      'journey.step.transport.bullet.3':
          'Long drives safety stops के साथ plan करें',
      'journey.step.money_taxes.title': 'वेतन, टैक्स और सुपर',
      'journey.step.money_taxes.description':
          'Payslips, taxes और superannuation समझें.',
      'journey.step.money_taxes.tip':
          'अपना pay rate जानें और हर payslip save करें.',
      'journey.step.money_taxes.bullet.0': 'Minimum pay rate जानें',
      'journey.step.money_taxes.bullet.1':
          'Problems accept करने से पहले payslips पढ़ें',
      'journey.step.money_taxes.bullet.2': 'Tax और super basics समझें',
      'journey.step.money_taxes.bullet.3':
          'Refunds और claims के लिए records रखें',
      'journey.step.visa_requirements.check.0':
          'WHV या Student Visa path चुनें',
      'journey.step.visa_requirements.check.1': 'Passport validity check करें',
      'journey.step.visa_requirements.check.2':
          'अपने country के visa requirements review करें',
      'journey.step.visa_requirements.check.3':
          'अगर लागू हो तो English/IELTS check करें',
      'journey.step.visa_requirements.check.4':
          'जरूरत हो तो health insurance prepare करें',
      'journey.step.visa_requirements.check.5': 'Proof of funds prepare करें',
      'journey.step.visa_requirements.check.6':
          'अगर लागू हो तो education documents prepare करें',
      'journey.step.visa_requirements.check.7':
          'ImmiAccount create या access करें',
      'journey.step.visa_requirements.check.8':
          'Official immigration links save करें',
      'journey.step.before_arrival.check.0':
          'Travel insurance options compare करें',
      'journey.step.before_arrival.check.1': 'Australia की flight book करें',
      'journey.step.before_arrival.check.2': 'First nights book करें',
      'journey.step.before_arrival.check.3':
          'Arrival के लिए offline maps download करें',
      'journey.step.before_arrival.check.4':
          'Travel card या bank backup prepare करें',
      'journey.step.before_arrival.check.5':
          'eSIM या arrival SIM plan choose करें',
      'journey.step.before_arrival.check.6':
          'Important documents offline save करें',
      'journey.step.before_arrival.check.7':
          'Airport से hostel transport plan करें',
      'journey.step.arrival_steps.check.0': 'SIM या eSIM activate करें',
      'journey.step.arrival_steps.check.1': 'TFN apply करें',
      'journey.step.arrival_steps.check.2': 'Bank account open या prepare करें',
      'journey.step.arrival_steps.check.3': 'Super account details set up करें',
      'journey.step.arrival_steps.check.4':
          'Forms के लिए Australian phone number ready रखें',
      'journey.step.arrival_steps.check.5': 'Passport और visa copies save करें',
      'journey.step.arrival_steps.check.6': 'Certificates और IDs organise करें',
      'journey.step.arrival_steps.check.7': 'Emergency contacts store करें',
      'journey.step.housing.check.0': 'First hostel या short stay book करें',
      'journey.step.housing.check.1': 'Local housing groups join करें',
      'journey.step.housing.check.2': 'Area चुनने से पहले transport check करें',
      'journey.step.housing.check.3': 'Deposit budget prepare करें',
      'journey.step.housing.check.4':
          'Place verify करने से पहले payment avoid करें',
      'journey.step.housing.check.5': 'Commit करने से पहले room inspect करें',
      'journey.step.housing.check.6': 'Bills और bond conditions confirm करें',
      'journey.step.housing.check.7': 'Payments का written proof रखें',
      'journey.step.work.check.0': 'Australian-style CV prepare करें',
      'journey.step.work.check.1': 'Simple job tracker create करें',
      'journey.step.work.check.2': 'Short cover message prepare करें',
      'journey.step.work.check.3': 'Online apply करें',
      'journey.step.work.check.4': 'CVs in person दें',
      'journey.step.work.check.5': 'Managers को follow up करें',
      'journey.step.work.check.6': 'References और certificates save करें',
      'journey.step.work.check.7': 'Accept करने से पहले pay rate check करें',
      'journey.step.regional_and_extension.check.0':
          'Eligible postcode check करें',
      'journey.step.regional_and_extension.check.1':
          'Eligible industry और task confirm करें',
      'journey.step.regional_and_extension.check.2': 'Payslips save करें',
      'journey.step.regional_and_extension.check.3':
          'Days और employer details track करें',
      'journey.step.regional_and_extension.check.4':
          'Possible हो तो signed timesheets रखें',
      'journey.step.regional_and_extension.check.5':
          'ABN या employer details confirm करें',
      'journey.step.regional_and_extension.check.6':
          'Unclear cash-only offers avoid करें',
      'journey.step.regional_and_extension.check.7':
          'Second-year visa evidence backup करें',
      'journey.step.transport.check.0': 'Transport options compare करें',
      'journey.step.transport.check.1': 'Rego और insurance check करें',
      'journey.step.transport.check.2': 'Buy करने से पहले vehicle inspect करें',
      'journey.step.transport.check.3': 'Buy से पहले PPSR/VIN check करें',
      'journey.step.transport.check.4':
          'State के roadworthy rules confirm करें',
      'journey.step.transport.check.5': 'Fuel और repairs budget करें',
      'journey.step.transport.check.6':
          'Emergency kit और spare tyre prepare करें',
      'journey.step.transport.check.7': 'Long drives safely plan करें',
      'journey.step.money_taxes.check.0': 'Minimum pay rate learn करें',
      'journey.step.money_taxes.check.1': 'हर payslip check करें',
      'journey.step.money_taxes.check.2': 'Tax records रखें',
      'journey.step.money_taxes.check.3':
          'Confirm करें कि employers को TFN दी है',
      'journey.step.money_taxes.check.4': 'Check करें कि super pay हो रहा है',
      'journey.step.money_taxes.check.5': 'Superannuation details save करें',
      'journey.step.money_taxes.check.6': 'Bank और employer records रखें',
      'journey.step.money_taxes.check.7':
          'Tax return season के लिए prepare करें',
      'kangaroo.bubble': 'मुझे Australia में आपकी मदद करने दें 🇦🇺',
      'visa.types.title': 'वीज़ा और आवश्यकताएँ',
      'visa.types.heading': 'वीज़ा के प्रकार',
      'visa.types.whv': 'वर्क एंड हॉलिडे वीज़ा',
      'visa.types.student': 'स्टूडेंट वीज़ा',
      'visa.whv.b1': 'यात्रा और फुल-टाइम काम',
      'visa.whv.b2': 'नियोक्ता आसानी से बदलें',
      'visa.whv.b3': 'Australia घूमते हुए बचत करें',
      'visa.whv.b4': 'Adventure और काम के लिए',
      'visa.whv.b5': 'Short-term plans के लिए अच्छा',
      'visa.student.b1': 'School, TAFE या uni में पढ़ाई',
      'visa.student.b2': 'सीमित घंटे काम',
      'visa.student.b3': 'लंबे भविष्य की तैयारी',
      'visa.student.b4': 'English या skills सुधारें',
      'visa.student.b5': 'Study-based plans के लिए बेहतर',
      'student.title': 'स्टूडेंट वीज़ा',
      'student.what_title': 'Student Visa क्या है?',
      'student.what_1':
          'Australia में eligible course में enrolled लोगों के लिए।',
      'student.what_2':
          'Schools, TAFE, universities या approved providers में पढ़ाई की अनुमति देता है।',
      'student.what_3': 'पढ़ाई के दौरान सीमित घंटे काम करने देता है।',
      'student.approval_title': 'अनुमानित approval time',
      'student.approval_body':
          'समय course, country, documents और application quality पर निर्भर करता है।',
      'student.requirements_title': 'स्टूडेंट वीज़ा आवश्यकताएँ',
      'student.req_1': 'वैध पासपोर्ट',
      'student.req_2': 'Approved provider से Confirmation of Enrolment',
      'student.req_3': 'Course, travel और living costs के लिए funds proof',
      'student.req_4': 'Overseas student health insurance',
      'student.req_5': 'जरूरत हो तो English level या education documents',
      'student.important_title': 'महत्वपूर्ण',
      'student.important_body':
          'Rules बदल सकते हैं। Apply करने से पहले official website जरूर देखें।',
      'student.apply_tab': 'कैसे apply करें',
      'student.requirements_tab': 'आवश्यकताएँ',
      'student.steps_title': 'आवेदन चरण',
      'student.step_1': 'Eligible course और provider चुनें।',
      'student.step_2': 'Confirmation of Enrolment लें।',
      'student.step_3': 'Documents, funds और health insurance तैयार करें।',
      'student.step_4': 'ImmiAccount से online apply करें।',
      'student.step_5': 'Final plans से पहले decision का इंतजार करें।',
      'student.balance_title': 'काम और पढ़ाई का संतुलन',
      'student.balance_body':
          'Budget को study के हिसाब से plan करें। Work rights limited होते हैं।',
      'student.support_title': 'स्टूडेंट वीज़ा सहायता',
      'student.support_body':
          'Visa या study centres में मदद के लिए YouTooProject से संपर्क करें।',
      'student.official_title': 'आधिकारिक जानकारी',
      'student.official_button': 'Student Visa details देखें',
      'student.support_button': 'YouTooProject',
      'insurance.title': 'यात्रा बीमा',
      'insurance.recommended': 'अनुशंसित बीमा',
      'insurance.compare': 'WHV insurance compare करें',
      'flights.title': 'फ्लाइट्स',
      'flights.buy': 'Flights खरीदें',
      'hostels.where': 'Hostels कहाँ book करें',
      'banks.title': 'अंतरराष्ट्रीय बैंक',
      'banks.suggested': 'सुझाए गए अंतरराष्ट्रीय बैंक',
      'banks.go_n26': 'N26 पर जाएं',
      'esims.popular': 'लोकप्रिय ई-सिम',
      'resource.insurance.subtitle':
          'Useful travel insurance options compare करें.',
      'resource.youtoo.subtitle': 'Student visa और study support.',
      'resource.flights.subtitle': 'Flights booking के useful partners.',
      'resource.hostels.subtitle': 'Australia में पहली रातें खोजें.',
      'resource.banks.subtitle': 'Arrival के लिए cards और accounts.',
      'resource.esims.subtitle': 'Land करते ही internet ready.',
      'donation.title': 'WorkyDay को सपोर्ट करें',
      'donation.body':
          'WorkyDay Australia में Working Holiday travellers के लिए free app है। अगर इससे मदद मिली, तो project support कर सकते हैं।',
      'donation.button': 'मुझे कॉफी पिलाएं ☕',
      'profile.automatic_email': 'ऑटोमैटिक ईमेल एडिटिंग',
      'profile.favourites': 'पसंदीदा',
      'profile.send_report': 'Report भेजें',
      'profile.support': 'मुझे कॉफी पिलाएं',
      'profile.title': 'प्रोफ़ाइल',
      'profile.settings': 'प्रोफ़ाइल सेटिंग्स',
      'profile.settings_body':
          'Automatic email, favourites और app tools setup करें.',
      'map.place_unknown': 'अज्ञात जगह',
      'map.google_paused': 'Google Maps temporarily paused है.',
      'map.dialog.profile': 'प्रोफ़ाइल',
      'map.error.invalid_place': 'इस जगह की valid ID नहीं है.',
      'map.worked.title': 'क्या आपने यहां काम किया है?',
      'map.worked.subtitle': 'आपका feedback दूसरे users की मदद करता है.',
      'map.worked.no': 'नहीं',
      'map.worked.already_title': 'पहले से चुना गया',
      'map.worked.already_body': 'यह जगह आपकी worked list में पहले से है.',
      'map.worked.saved_local':
          'इस device पर saved है. Sync बाद में हो सकता है.',
      'map.email.copy': 'Email copy करें',
      'map.email.send': 'Email भेजें',
      'map.email.copied': 'ईमेल कॉपी हुआ',
      'map.location.denied':
          'Location access denied है. Allow करने के लिए फिर tap करें.',
      'map.location.services_off': 'Location services बंद हैं.',
      'map.location.settings': 'सेटिंग्स',
      'map.location.unavailable': 'अभी आपकी location नहीं मिल सकी.',
      'map.location.blocked':
          'Location blocked है. Settings खोलकर Location allow करें.',
      'map.location.settings_failed': 'Location settings नहीं खुल सकीं.',
      'map.tooltip.worked_here': 'मैंने यहां काम किया',
      'map.tooltip.copy_phone': 'Phone copy करें',
      'map.tooltip.email_options': 'ईमेल विकल्प',
      'map.tooltip.open_facebook': 'Facebook खोलें',
      'map.tooltip.view_jobs': 'Job offers देखें',
      'map.tooltip.open_instagram': 'Instagram खोलें',
      'map.tooltip.add_favourite': 'Favourites में जोड़ें',
      'map.tooltip.remove_favourite': 'Favourites से हटाएं',
      'map.tooltip.directions': 'दिशा-निर्देश',
      'map.filter.title': 'फ़िल्टर',
      'map.filter.show_without_contact': 'बिना web/contact वाली places दिखाएं',
      'favorites.empty': 'अभी कोई पसंदीदा नहीं',
      'favorites.load_error': 'Favourites load नहीं हुए. फिर कोशिश करें.',
      'review.title': 'क्या आपको WorkyDay पसंद आ रहा है?',
      'review.body':
          'WorkyDay अभी शुरू ही हुआ है। ऐप को रेट करें और हमें अपना पसंदीदा फीचर बताएं।',
      'review.not_now': 'अभी नहीं',
      'review.rate_app': 'ऐप रेट करें',
      'mail.save_message': 'मैसेज सेव करें',
      'mail.message_hint': 'अपना मैसेज यहाँ लिखें...',
      'mail.email_content': 'ईमेल सामग्री',
      'mail.upload_cv': 'CV upload करें (PDF)',
      'mail.replace_cv': 'CV replace करें (PDF)',
      'mail.current_cv': 'मौजूदा CV',
      'mail.no_cv': 'कोई नहीं',
      'forum.ask': 'फोरम से पूछें',
      'error.oops': 'ओह! ',
      'error.link_title': 'लिंक नहीं चला',
      'error.link_message': 'यह link अभी उपलब्ध नहीं है।',
      'error.try_report': 'बाद में कोशिश करें या report करें।',
      'error.load_title': 'लोड नहीं हुआ',
      'error.load_message': 'कुछ गलत हुआ। फिर कोशिश करें।',
      'error.email_title': 'ईमेल नहीं खुला',
      'error.email_message': 'Email app नहीं खुल सकी।',
      'error.email_helper': 'Mail setup जांचें या report करें।',
      'onboarding.skip': 'छोड़ें',
      'onboarding.welcome.title': 'WorkyDay में आपका स्वागत है 👋',
      'onboarding.welcome.description':
          'Australia Working Holiday के लिए jobs और useful info खोजें.\nएक quick tour करते हैं.',
      'onboarding.welcome.primary': 'टूर शुरू करें',
      'onboarding.map.title': 'अपने आसपास workplaces खोजें',
      'onboarding.map.description':
          'Details देखने और employers से contact करने के लिए place tap करें.',
      'onboarding.map.primary': 'आगे',
      'onboarding.automatic_email.title': 'Employers से जल्दी contact करें',
      'onboarding.automatic_email.description':
          'Message और CV एक बार save करें, फिर applications तेज भेजें.',
      'onboarding.automatic_email.primary': 'आगे',
      'onboarding.guide.title': 'ऑस्ट्रेलिया गाइड',
      'onboarding.guide.description':
          'आपकी Working Holiday के लिए जरूरी चीजें:',
      'onboarding.guide.bullet.0': 'वीज़ा आवश्यकताएँ',
      'onboarding.guide.bullet.1': 'नौकरियाँ',
      'onboarding.guide.bullet.2': 'रहना',
      'onboarding.guide.bullet.3': 'टैक्स और सुपर',
      'onboarding.guide.primary': 'आगे',
      'onboarding.guide_kangaroo.title': 'आपकी ऑस्ट्रेलिया यात्रा',
      'onboarding.guide_kangaroo.description':
          'Guided journey और checklist खोलने के लिए kangaroo tap करें.',
      'onboarding.guide_kangaroo.primary': 'समाप्त करें',
    },
  };

  static Map<String, String> forCode(String? code) {
    return _values[_normalize(code)] ?? _values['en']!;
  }

  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsLanguageKey);
    final system =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return forCode(saved?.isNotEmpty == true ? saved : system);
  }

  static String t(Map<String, String> strings, String key) {
    return strings[key] ?? _values['en']![key] ?? key;
  }

  static String _normalize(String? code) {
    final language = (code ?? 'en').split(RegExp('[-_]')).first.toLowerCase();
    return _values.containsKey(language) ? language : 'en';
  }
}
