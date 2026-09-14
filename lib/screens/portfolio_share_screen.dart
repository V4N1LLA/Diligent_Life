import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/portfolio_repository.dart';
import '../services/portfolio_share.dart';

class PortfolioShareScreen extends StatefulWidget {
  const PortfolioShareScreen({
    super.key,
    required this.data,
    required this.title,
  });
  final PortfolioData data;
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
    _image = portfolioShareImage(widget.data, widget.title);
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
          fileNameOverrides: ['diligent-life-portfolio.png'],
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('포트폴리오 공유')),
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
            padding: const EdgeInsets.all(20),
            children: [
              const Text('선택한 기간의 움직임과 몸무게 변화가 포함돼요. 경로 위치는 포함하지 않아요.'),
              const SizedBox(height: 16),
              Image.memory(
                snapshot.data!,
                semanticLabel: '${widget.title} 이미지 카드',
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
            ],
          );
        },
      ),
    ),
  );
}
