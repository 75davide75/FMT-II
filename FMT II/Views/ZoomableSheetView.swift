import SwiftUI
import UIKit

/// UIScrollView con pinch-zoom e pan per contenuto SwiftUI: è il "foglio" del
/// builder dell'orario (design 3d). Espone lo zoom e il rettangolo visibile in
/// coordinate unitarie (0–1) per pilotare il controllo zoom e la minimappa.
struct ZoomableSheetView<Content: View>: UIViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var visibleRect: CGRect
    var minZoom: CGFloat = 0.5
    var maxZoom: CGFloat = 2
    /// Vero mentre l'utente sta pizzicando: il contenuto può usarlo per non
    /// scambiare l'appoggio delle due dita per un tap.
    var isPinching: Binding<Bool>? = nil
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = minZoom
        scroll.maximumZoomScale = maxZoom
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        context.coordinator.host = host
        scroll.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor)
        ])
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self   // binding sempre aggiornati
        context.coordinator.host?.rootView = content()
        context.coordinator.linkGesturesIfNeeded(in: scroll)
        // Zoom pilotato dai bottoni − / +; mai durante il pinch dell'utente.
        if abs(scroll.zoomScale - zoom) > 0.01, !context.coordinator.isInteracting {
            scroll.setZoomScale(zoom, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableSheetView
        var host: UIHostingController<Content>?
        var isInteracting = false
        private var linkedRecognizers = Set<ObjectIdentifier>()

        init(_ parent: ZoomableSheetView) { self.parent = parent }

        /// I tap del contenuto SwiftUI (le celle) devono aspettare il
        /// fallimento del pinch: altrimenti appoggiando due dita capita che
        /// il tocco venga preso come tap su una casella invece che come zoom.
        /// (Il pinch fallisce al touch-up di un tocco singolo, quindi i tap
        /// normali non subiscono ritardi percepibili.)
        func linkGesturesIfNeeded(in scroll: UIScrollView) {
            guard let pinch = scroll.pinchGestureRecognizer,
                  let recognizers = host?.view.gestureRecognizers else { return }
            for r in recognizers where r !== pinch {
                let id = ObjectIdentifier(r)
                if !linkedRecognizers.contains(id) {
                    r.require(toFail: pinch)
                    linkedRecognizers.insert(id)
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewWillBeginZooming(_ s: UIScrollView, with view: UIView?) {
            isInteracting = true
            DispatchQueue.main.async { self.parent.isPinching?.wrappedValue = true }
        }

        func scrollViewDidEndZooming(_ s: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isInteracting = false
            DispatchQueue.main.async { self.parent.zoom = scale }
            // Piccola coda: copre il tap "ritardato" della cella partito
            // mentre il pinch stava iniziando.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.parent.isPinching?.wrappedValue = false
            }
        }

        func scrollViewDidZoom(_ s: UIScrollView) { publish(s) }
        func scrollViewDidScroll(_ s: UIScrollView) { publish(s) }

        private func publish(_ s: UIScrollView) {
            let size = s.contentSize
            guard size.width > 0, size.height > 0 else { return }
            let r = CGRect(x: max(0, s.contentOffset.x / size.width),
                           y: max(0, s.contentOffset.y / size.height),
                           width: min(s.bounds.width / size.width, 1),
                           height: min(s.bounds.height / size.height, 1))
            let scale = s.zoomScale
            let interacting = isInteracting
            DispatchQueue.main.async {
                self.parent.visibleRect = r
                if interacting { self.parent.zoom = scale }
            }
        }
    }
}
