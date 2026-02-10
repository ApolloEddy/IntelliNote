
class _GreetingText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 6) {
      greeting = '夜深了';
    } else if (hour < 12) {
      greeting = '早上好';
    } else if (hour < 14) {
      greeting = '中午好';
    } else if (hour < 18) {
      greeting = '下午好';
    } else {
      greeting = '晚上好';
    }

    return Text(
      '$greeting, Eddy',
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}
