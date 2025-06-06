import SwiftUI

struct UndoToastView: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100) // Position above tab bar
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
        .onAppear {
            // Auto-hide after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    isShowing = false
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        UndoToastView(message: "Restored subscription to \"Tech Talk Daily\"", isShowing: .constant(true))
    }
} 