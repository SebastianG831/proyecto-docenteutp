import { Component } from '@angular/core';
import { Router } from '@angular/router';

@Component({
  selector: 'app-home',
  standalone: true,
  templateUrl: './home.component.html',
  styleUrl: './home.component.scss',
})
export class HomeComponent {
  searchTerm = '';

  constructor(private router: Router) {}

  onSearch(event: SubmitEvent): void {
    event.preventDefault();
    const query = this.searchTerm.trim();
    if (query) {
      this.router.navigate(['/buscar'], { queryParams: { q: query } });
    }
  }
}