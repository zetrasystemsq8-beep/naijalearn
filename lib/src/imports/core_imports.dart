// Flutter SDK
export 'package:flutter/material.dart';
export 'package:flutter/cupertino.dart' hide RefreshCallback;
export 'package:flutter/foundation.dart';
export 'package:flutter/services.dart';
export 'package:flutter_native_splash/flutter_native_splash.dart';

export 'package:easy_localization/easy_localization.dart' hide TextDirection, MapExtension;

// Project Core — everything exported through shared.dart (theme, extensions,
// utils, widgets, enums) plus routing and services.
export '../config/app_config.dart';
export '../routing/app_router.dart';
export '../routing/app_routes.dart';
export '../routing/global_navigator.dart';
export '../services/services.dart';
export '../shared/shared.dart';

export '../features/auth/presentation/screens/login_screen.dart';
export '../features/auth/presentation/screens/signup_screen.dart';
export '../features/auth/presentation/screens/forgot_password_screen.dart';
export '../features/home/presentation/screens/home_page.dart';
export '../features/onboarding/presentation/screens/onboarding_page.dart';

// Nigeria Features
export '../features/nigeria/presentation/screens/nigeria_news_screen.dart';
export '../features/nigeria/presentation/screens/government_services_screen.dart';
export '../features/nigeria/presentation/screens/wiki_search_screen.dart';

// Phase 3 Features
export '../features/settings/presentation/screens/settings_screen.dart';
export '../features/profile/presentation/screens/profile_screen.dart';
export '../features/search/presentation/screens/search_screen.dart';
