//
//  SplashScreenView.swift
//  Invelio
//
//  Created by Vira Fitriyani on 26/09/26.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var logoOpacity: Double = 0
    @State private var sweepOffset: CGFloat = -1.5
    @State private var isFinished = false

    var body: some View {
        ZStack {
            Color.DarkPurpleAppBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("invelio-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .overlay(
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.25),
                                    .white.opacity(0.6),
                                    .white.opacity(0.25),
                                    .clear
                                ],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                            .frame(width: geo.size.width * 0.9)
                            .offset(x: sweepOffset * geo.size.width)
                            .clipped()
                        }
                        .mask(
                            Image("invelio-icon")
                                .resizable()
                                .scaledToFit()
                        )
                    )

//                Text("Invelio")
//                    .font(.system(size: 28, weight: .semibold, design: .rounded))
//                    .foregroundColor(.white)
            }
            .opacity(logoOpacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) {
                logoOpacity = 1
            }

            withAnimation(.easeInOut(duration: 1.6).delay(0.8)) {
                sweepOffset = 1.5
            }

            withAnimation(.easeOut(duration: 0.6).delay(2.8)) {
                logoOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFinished = true
                }
            }
        }
        .opacity(isFinished ? 0 : 1)
    }

    var hasFinished: Bool {
        isFinished
    }
}

#Preview {
    SplashScreenView()
}
