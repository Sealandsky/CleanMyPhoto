//
//  YearIndexBar.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/3/29.
//

import SwiftUI

struct YearIndexBar: View {
    let years: [Int]
    @Binding var scrollToYear: Int?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(years, id: \.self) { year in
                Text("\(year)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 20)
                    .onTapGesture {
                        scrollToYear = year
                    }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.6))
                .blur(radius: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}
