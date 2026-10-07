import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../data/portfolio_repository.dart';
import '../services/portfolio_share.dart';
import '../theme/app_theme.dart';

class PortfolioShareScreen extends StatefulWidget {
  const PortfolioShareScreen({
    super.key,
    required this.data,
    required this.title,
  }) : image = null,
       notice = null,
       fileName = null;
  const PortfolioShareScreen.report({
    super.key,
    required this.title,
    required this.image,
  }) : data = null,
       notice = null,
       fileName = null;
  const PortfolioShareScreen.image({
    super.key,
    required this.title,
    required this.image,
    required this.notice,
    required this.fileName,
  }) : data = null;
  final String? notice, fileName;
  final PortfolioData? data;
  final Future<Uint8List> Function()? image;
  final String title;
  @override
  State<PortfolioShareScreen> createState() => _PortfolioShareScreenState();
}

class _PortfolioShareScreenState extends State<PortfolioShareScreen> {
  late Future<Uint8List> _image;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _image = widget.image == null
        ? portfolioShareImage(widget.data!, widget.title)
        : Future.sync(widget.image!);
    _image.ignore();
  }

  Future<void> _share(BuildContext buttonContext, Uint8List bytes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final box = buttonContext.findRenderObject()! as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [
            widget.fileName ??
                (widget.image == null
                    ? 'diligent-life-portfolio.png'
                    : 'diligent-life-report.png'),
          ],
          title: widget.title,
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '공유창을 열지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(Uint8List bytes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const MethodChannel('diligent_life/gallery').invokeMethod<String>(
        'save',
        {'bytes': bytes, 'name': widget.fileName ?? 'diligent-life-card.png'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('갤러리의 Diligent Life 폴더에 저장했어요.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '이미지를 저장하지 못했어요. Android 10 이상에서 저장 공간을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.notice != null
            ? '공유 카드'
            : widget.image == null
            ? '포트폴리오 공유'
            : '리포트 공유',
      ),
    ),
    body: SafeArea(
      child: FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(_load),
                child: const Text('카드 생성 다시 시도'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpace.page),
            children: [
              Text(
                widget.notice ?? '선택한 기간의 움직임과 몸무게 변화가 포함돼요. 경로 위치는 포함하지 않아요.',
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppStyle.radius),
                child: Image.memory(
                  snapshot.data!,
                  semanticLabel: '${widget.title} 이미지 카드',
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!),
              Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _share(context, snapshot.data!),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('이미지 공유'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _save(snapshot.data!),
                icon: const Icon(Icons.save_alt),
                label: const Text('갤러리에 저장'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
