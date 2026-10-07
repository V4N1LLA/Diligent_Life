import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ThemeSelector extends StatelessWidget {
  const ThemeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;
  static const options = [
    (ThemeMode.system, '시스템 설정 따르기', Icons.brightness_auto_outlined),
    (ThemeMode.light, '라이트', Icons.light_mode_outlined),
    (ThemeMode.dark, '다크', Icons.dark_mode_outlined),
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('테마', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpace.large),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 480 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18) {
            return SegmentedButton<ThemeMode>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 56)),
              ),
              segments: [
                for (final (mode, label, _) in options)
                  ButtonSegment(value: mode, label: Text(label)),
              ],
              selected: {value},
              onSelectionChanged: (values) => onChanged(values.single),
            );
          }
          return Column(
            children: [
              for (final (mode, label, icon) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.small),
                  child: Material(
                    color: value == mode
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppStyle.controlRadius),
                    child: Semantics(
                      selected: value == mode,
                      inMutuallyExclusiveGroup: true,
                      child: ListTile(
                        minTileHeight: 64,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppStyle.controlRadius,
                          ),
                        ),
                        leading: Icon(icon),
                        title: Text(label),
                        trailing: Icon(
                          value == mode
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => onChanged(mode),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
